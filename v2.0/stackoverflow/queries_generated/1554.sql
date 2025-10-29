-- {"query": "1554.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2640} 
WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.UpVotes,
        u.DownVotes,
        COALESCE(u.Views, 0) AS UserViews,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(p.CommentCount, 0)) AS TotalPostComments,
        AVG(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate))) AS AvgPostLifetimeSeconds,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(COALESCE(c.Score, 0)) AS TotalCommentScore,
        MAX(b.Date) AS LastBadgeDate,
        MIN(b.Date) AS FirstBadgeDate,
        COUNT(b.Id) AS TotalBadges,
        MAX(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS HasGoldBadge,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC) AS ReputationRank,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.LastAccessDate DESC) AS AccessRankInYear,
        LAG(u.Reputation, 1, 0) OVER (ORDER BY u.CreationDate) AS PrevUserReputation
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes, u.Views
),
PostComplexMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        p.Tags,
        p.Title,
        p.AcceptedAnswerId,
        ph.CreationDate AS HistoryDate,
        ph.PostHistoryTypeId,
        ph.Text AS PostHistoryText,
        ph.Comment AS HistoryComment,
        pl.RelatedPostId AS LinkedPostId,
        pl.LinkTypeId,
        (SELECT COUNT(DISTINCT co.UserId)
         FROM Comments co
         WHERE co.PostId = p.Id AND co.CreationDate BETWEEN p.CreationDate AND p.CreationDate + INTERVAL '24 hours') AS UniqueCommentersFirstDay,
        AVG(CASE WHEN v.VoteTypeId = 2 THEN 1.0 ELSE 0.0 END) OVER (PARTITION BY p.OwnerUserId) AS AvgUpvoteRatioForOwner,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS TotalBountyGiven,
        SUM(CASE WHEN v.VoteTypeId = 9 THEN v.BountyAmount ELSE 0 END) AS TotalBountyReceived,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.UserId ELSE NULL END) AS UpvotingUsersCount
    FROM
        Posts p
    LEFT JOIN
        PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN
        PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN
        Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3, 8, 9) -- UpMod, DownMod, BountyStart, BountyClose
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.FavoriteCount, p.Tags, p.Title, p.AcceptedAnswerId,
        ph.CreationDate, ph.PostHistoryTypeId, ph.Text, ph.Comment, pl.RelatedPostId, pl.LinkTypeId
),
AggregatedTags AS (
    SELECT
        pcm.PostId,
        unnest(string_to_array(SUBSTRING(TRIM(BOTH '<>' FROM pcm.Tags), 1, LENGTH(TRIM(BOTH '<>' FROM pcm.Tags))), '><')) AS TagName
    FROM
        PostComplexMetrics pcm
    WHERE
        pcm.Tags IS NOT NULL
        AND pcm.PostTypeId = 1 -- Only questions have meaningful tags
),
TopQuestionTags AS (
    SELECT
        TagName,
        COUNT(DISTINCT PostId) AS TaggedQuestionCount,
        RANK() OVER (ORDER BY COUNT(DISTINCT PostId) DESC) AS TagPopularityRank
    FROM
        AggregatedTags
    GROUP BY
        TagName
    HAVING
        COUNT(DISTINCT PostId) > 100
)
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.TotalQuestions,
    ue.TotalAnswers,
    ue.TotalBadges,
    ue.HasGoldBadge,
    ue.ReputationRank,
    ue.AccessRankInYear,
    ue.PrevUserReputation,
    pcm.PostId,
    pcm.PostCreationDate,
    pcm.PostScore,
    pcm.ViewCount,
    pcm.AnswerCount,
    pcm.FavoriteCount,
    pcm.Title,
    pcm.UniqueCommentersFirstDay,
    COALESCE(pcm.AvgUpvoteRatioForOwner, 0.0) AS OwnerAvgUpvoteRatio,
    COALESCE(pcm.TotalBountyGiven, 0) AS TotalBountyGivenByPost,
    COALESCE(pcm.TotalBountyReceived, 0) AS TotalBountyReceivedByPost,
    pcm.UpvotingUsersCount,
    tqt.TagName AS TopAssociatedTag,
    tqt.TaggedQuestionCount AS TopTaggedQuestionCount,
    tqt.TagPopularityRank,
    (ue.Reputation * (ue.UpVotes - ue.DownVotes + COALESCE(ue.TotalPostScore, 0))) / (1.0 + ABS(EXTRACT(DAY FROM (NOW() - ue.LastAccessDate)))) AS UserEngagementScore,
    CASE
        WHEN ue.Reputation >= 10000 AND ue.HasGoldBadge = 1 AND ue.TotalQuestions > 50 THEN 'High-Tier Veteran'
        WHEN ue.Reputation >= 2000 AND ue.TotalAnswers > 20 AND ue.AvgPostLifetimeSeconds IS NOT NULL THEN 'Active Contributor'
        WHEN ue.Reputation < 1000 AND ue.TotalCommentsMade > 100 THEN 'Engaged Commenter'
        ELSE 'Casual User'
    END AS UserCategory,
    COALESCE(LOWER(SUBSTRING(pcm.Title, 1, 10)), 'no_title_prefix') || '_' || TRUNC(RANDOM() * 10000)::TEXT AS DerivedPostCode,
    (SELECT p_ans.Body
     FROM Posts p_ans
     WHERE p_ans.Id = pcm.AcceptedAnswerId AND p_ans.PostTypeId = 2
     LIMIT 1) AS AcceptedAnswerBodySnippet, -- Correlated Subquery in SELECT
    (SELECT COUNT(DISTINCT ph2.UserId)
     FROM PostHistory ph2
     WHERE ph2.PostId = pcm.PostId AND ph2.PostHistoryTypeId IN (4,5,6) AND ph2.UserId IS NOT NULL
     HAVING COUNT(DISTINCT ph2.UserId) > 1) AS MultipleEditorsExcludingOwner
FROM
    UserEngagement ue
INNER JOIN
    PostComplexMetrics pcm ON ue.UserId = pcm.OwnerUserId
LEFT JOIN LATERAL ( -- Lateral join for the top tag
    SELECT TagName, TaggedQuestionCount, TagPopularityRank
    FROM AggregatedTags at
    INNER JOIN TopQuestionTags tqt_inner ON at.TagName = tqt_inner.TagName
    WHERE at.PostId = pcm.PostId
    ORDER BY tqt_inner.TagPopularityRank ASC
    LIMIT 1
) AS tqt ON TRUE
WHERE
    ue.Reputation >= 1000
    AND pcm.PostScore > 5
    AND pcm.PostTypeId = 1 -- Only questions for the main output
    AND pcm.PostCreationDate >= ue.UserCreationDate + INTERVAL '30 days' -- Post creation after user has been active for a month
    AND pcm.Title IS NOT NULL
    AND pcm.Tags IS NOT NULL
    AND pcm.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1 AND CreationDate >= NOW() - INTERVAL '1 year') -- Posts with above-average recent views
    AND EXISTS ( -- Correlated subquery in WHERE clause
        SELECT 1
        FROM PostHistory ph_exist
        WHERE ph_exist.PostId = pcm.PostId
          AND ph_exist.PostHistoryTypeId = 10 -- Post closed
          AND ph_exist.CreationDate BETWEEN pcm.PostCreationDate AND pcm.PostCreationDate + INTERVAL '1 year'
    )
UNION ALL
-- Another path: Users who are active but might not have many posts, focusing on comments or badges
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.TotalQuestions,
    ue.TotalAnswers,
    ue.TotalBadges,
    ue.HasGoldBadge,
    ue.ReputationRank,
    ue.AccessRankInYear,
    ue.PrevUserReputation,
    NULL AS PostId,
    NULL AS PostCreationDate,
    NULL AS PostScore,
    NULL AS ViewCount,
    NULL AS AnswerCount,
    NULL AS FavoriteCount,
    NULL AS Title,
    NULL AS UniqueCommentersFirstDay,
    NULL AS OwnerAvgUpvoteRatio,
    NULL AS TotalBountyGivenByPost,
    NULL AS TotalBountyReceivedByPost,
    NULL AS UpvotingUsersCount,
    NULL AS TopAssociatedTag,
    NULL AS TopTaggedQuestionCount,
    NULL AS TagPopularityRank,
    (ue.Reputation * (ue.UpVotes + COALESCE(ue.TotalCommentScore, 0))) / (1.0 + ABS(EXTRACT(DAY FROM (NOW() - ue.LastAccessDate)))) AS UserEngagementScore,
    'Comment-Focused User' AS UserCategory,
    'NA_' || TRUNC(RANDOM() * 10000)::TEXT AS DerivedPostCode,
    NULL AS AcceptedAnswerBodySnippet,
    NULL AS MultipleEditorsExcludingOwner
FROM
    UserEngagement ue
WHERE
    ue.TotalCommentsMade >= 500
    AND ue.TotalPosts = 0
    AND ue.Reputation >= 500
    AND ue.LastAccessDate >= NOW() - INTERVAL '6 months'
ORDER BY
    UserEngagementScore DESC, ReputationRank ASC, TotalBadges DESC;