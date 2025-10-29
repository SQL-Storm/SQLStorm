-- {"query": "1358.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2321} 

WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COALESCE(u.DisplayName, 'Anonymous') AS UserDisplayName,
        u.LastAccessDate,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        EXTRACT(YEAR FROM CURRENT_TIMESTAMP) - EXTRACT(YEAR FROM u.CreationDate) AS YearsOnPlatform,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgesCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgesCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgesCount,
        COUNT(b.Id) AS TotalBadges,
        MAX(b.Date) AS LatestBadgeDate,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS AvgQuestionScoreByUser,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AvgAnswerScoreByUser
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY
        u.Id, u.Reputation, u.CreationDate, u.DisplayName, u.LastAccessDate,
        u.Views, u.UpVotes, u.DownVotes
),
PostBaseMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        COALESCE(p.Title, 'No Title Provided') AS PostTitle,
        -- Safely parse tags: handle NULL or empty string after trimming <>
        CASE
            WHEN p.Tags IS NULL OR TRIM(p.Tags) = '<>' THEN NULL
            ELSE string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><')
        END AS TagsArray,
        p.AnswerCount,
        p.CommentCount AS PostCommentCount,
        p.FavoriteCount,
        p.AcceptedAnswerId,
        p.ParentId,
        p.ClosedDate,
        p.CommunityOwnedDate,
        (CURRENT_TIMESTAMP - p.CreationDate) AS PostAgeInterval,
        (CASE WHEN p.PostTypeId = 1 THEN TRUE ELSE FALSE END) AS IsQuestion,
        (CASE WHEN p.ClosedDate IS NOT NULL THEN TRUE ELSE FALSE END) AS IsClosed,
        (CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN TRUE ELSE FALSE END) AS IsCommunityOwned
    FROM Posts p
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
),
LatestPostContentEdit AS (
    SELECT
        ph.PostId,
        ph.UserId AS LastEditorUserId,
        u.DisplayName AS LastEditorDisplayName,
        ph.CreationDate AS LastEditDate,
        ph.Text AS LastEditText,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    LEFT JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (5, 6, 8) -- Edit Body, Edit Tags, Rollback Body
),
QuestionTagPerformance AS (
    SELECT
        unnested_tag AS TagName,
        COUNT(DISTINCT pbm.PostId) AS TotalQuestionsInTag,
        AVG(pbm.PostScore) AS AvgScoreForTag,
        AVG(pbm.AnswerCount) AS AvgAnswersForTag,
        SUM(pbm.FavoriteCount) AS TotalFavoritesForTag,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT pbm.PostId) DESC, AVG(pbm.PostScore) DESC) AS TagPopularityRank
    FROM PostBaseMetrics pbm
    JOIN LATERAL UNNEST(pbm.TagsArray) AS unnested_tag ON pbm.IsQuestion AND pbm.TagsArray IS NOT NULL
    GROUP BY unnested_tag
),
ActiveContributors AS (
    SELECT UserId FROM Badges WHERE Class = 1 -- Gold badge holders
    UNION
    SELECT OwnerUserId AS UserId FROM Posts WHERE PostTypeId = 2 GROUP BY OwnerUserId HAVING COUNT(Id) > 50 -- Users with >50 answers
    UNION
    SELECT UserId FROM PostHistory WHERE PostHistoryTypeId IN (5, 6) GROUP BY UserId HAVING COUNT(Id) > 20 -- Users with >20 content edits
)
SELECT
    ue.UserId,
    ue.UserDisplayName,
    ue.Reputation,
    ue.YearsOnPlatform,
    ue.GoldBadgesCount,
    ue.TotalBadges,
    COALESCE(ue.AvgQuestionScoreByUser, 0) AS AvgQuestionScoreByUser,
    COALESCE(ue.AvgAnswerScoreByUser, 0) AS AvgAnswerScoreByUser,
    ac.UserId IS NOT NULL AS IsActiveContributor,
    COALESCE(SUM(pbm.PostScore), 0) AS TotalPostsScore,
    COALESCE(SUM(pbm.ViewCount), 0) AS TotalPostsViewCount,
    COALESCE(COUNT(DISTINCT pbm.PostId), 0) AS TotalPostsAuthored,
    -- Correlated Subquery: Avg comment score across all posts owned by this user
    (SELECT COALESCE(AVG(c.Score), 0)
     FROM Comments c
     WHERE c.UserId = ue.UserId) AS AvgCommentScoreByAuthor,
    -- Complex calculation combining post metrics
    SUM(
        COALESCE(pbm.PostScore, 0) * 0.4 +
        COALESCE(pbm.ViewCount, 0) * 0.05 +
        COALESCE(pbm.AnswerCount, 0) * 0.2 +
        COALESCE(pbm.PostCommentCount, 0) * 0.15 +
        COALESCE(pbm.FavoriteCount, 0) * 0.2
    ) AS WeightedEngagementScore,
    -- Window Function: Rank users by reputation within their 'years on platform' tier
    RANK() OVER (PARTITION BY ue.YearsOnPlatform ORDER BY ue.Reputation DESC, ue.UserUpVotes DESC) AS RankInYearsOnPlatform,
    -- NULL logic and string expression for post titles
    COALESCE(STRING_AGG(DISTINCT UPPER(SUBSTRING(pbm.PostTitle, 1, 1)) || '...' ORDER BY pbm.PostTitle) FILTER (WHERE pbm.PostTitle IS NOT NULL), 'N/A') AS FirstLettersOfTitles,
    -- Details from latest edit
    COALESCE(STRING_AGG(DISTINCT lpeh.LastEditorDisplayName || ' on ' || TO_CHAR(lpeh.LastEditDate, 'YYYY-MM-DD') ORDER BY lpeh.LastEditDate) FILTER (WHERE lpeh.LastEditorDisplayName IS NOT NULL), 'No recent edits') AS LatestEditSummary,
    -- Tag Performance details for questions by this user
    COALESCE(STRING_AGG(DISTINCT qtp.TagName || ' (Rank: ' || qtp.TagPopularityRank || ')' ORDER BY qtp.TagPopularityRank) FILTER (WHERE qtp.TagName IS NOT NULL), 'No relevant tags') AS TopTagsByContributor,
    -- Conditional check on post status and owner
    SUM(CASE WHEN pbm.IsClosed AND pbm.OwnerUserId = ue.UserId THEN 1 ELSE 0 END) AS ClosedPostsAuthored,
    SUM(CASE WHEN pbm.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer,
    -- Correlated Subquery: Get the score of the accepted answer for one of their questions
    (SELECT COALESCE(MAX(a.Score), 0)
     FROM Posts q
     JOIN Posts a ON q.AcceptedAnswerId = a.Id
     WHERE q.OwnerUserId = ue.UserId AND q.PostTypeId = 1
     AND q.CreationDate = (SELECT MAX(q2.CreationDate) FROM Posts q2 WHERE q2.OwnerUserId = ue.UserId AND q2.PostTypeId = 1)) AS LatestAcceptedAnswerScore,
    -- Conditional expression based on user and post attributes
    CASE
        WHEN ue.Reputation > 100000 AND ue.GoldBadgesCount >= 5 THEN 'Elite Contributor'
        WHEN ue.Reputation > 20000 OR ue.TotalBadges >= 50 THEN 'High-Impact Contributor'
        WHEN COALESCE(ue.AvgQuestionScoreByUser, 0) > 10 OR COALESCE(ue.AvgAnswerScoreByUser, 0) > 15 THEN 'Valuable Contributor'
        ELSE 'General Contributor'
    END AS ContributorTier
FROM UserEngagement ue
LEFT JOIN PostBaseMetrics pbm ON ue.UserId = pbm.OwnerUserId AND pbm.IsQuestion
LEFT JOIN LATERAL UNNEST(pbm.TagsArray) AS user_post_tag ON pbm.IsQuestion AND pbm.TagsArray IS NOT NULL
LEFT JOIN QuestionTagPerformance qtp ON user_post_tag = qtp.TagName
LEFT JOIN LatestPostContentEdit lpeh ON pbm.PostId = lpeh.PostId AND lpeh.rn = 1
LEFT JOIN ActiveContributors ac ON ue.UserId = ac.UserId
GROUP BY
    ue.UserId, ue.UserDisplayName, ue.Reputation, ue.YearsOnPlatform, ue.GoldBadgesCount,
    ue.TotalBadges, ue.AvgQuestionScoreByUser, ue.AvgAnswerScoreByUser, ac.UserId
HAVING
    SUM(COALESCE(pbm.ViewCount, 0)) > 1000
    AND ue.Reputation > 1000
ORDER BY
    WeightedEngagementScore DESC, ue.Reputation DESC
LIMIT 100;
