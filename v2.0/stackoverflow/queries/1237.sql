-- {"query": "1237.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3065}
WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(c.Score, 0)) AS TotalCommentScore,
        EXTRACT(YEAR FROM u.CreationDate) AS UserCreationYear,
        EXTRACT(MONTH FROM u.CreationDate) AS UserCreationMonth
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Reputation >= 1000
      AND u.LastAccessDate >= DATE '2020-01-01'
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
    HAVING COUNT(DISTINCT p.Id) > 10
),
PostDetailsWithHistory AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        COALESCE(p.Title, SUBSTRING(p.Body FROM 1 FOR 50) || '...') AS DisplayTitle,
        p.Tags,
        ph.CreationDate AS HistoryDate,
        ph.PostHistoryTypeId,
        ph.Comment AS HistoryComment,
        ph.UserId AS HistoryEditorUserId,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY ph.CreationDate DESC, ph.PostHistoryTypeId DESC) AS rn_latest_history,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE NULL END) OVER (PARTITION BY p.Id) AS EditCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN 1 ELSE NULL END) OVER (PARTITION BY p.Id) AS ModerationEventCount,
        (CASE WHEN p.Tags IS NOT NULL THEN regexp_split_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags) - 2), '><') ELSE NULL END) AS TagArray,
        (EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1)) AS HasLinkedPosts,
        (EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3)) AS HasDuplicatePosts,
        CASE
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'CommunityOwned'
            WHEN p.ViewCount > 10000 AND p.Score > 50 THEN 'HighVisibilityOpen'
            ELSE 'Open'
        END AS PostStatusClassifier
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.PostTypeId IN (1, 2)
      AND p.CreationDate >= DATE '2020-01-01'
),
RankedTagPerformance AS (
    SELECT
        t.TagName,
        SUM(p.Score) AS TotalTagScore,
        COUNT(p.Id) AS TotalTagPosts,
        AVG(p.ViewCount) AS AvgTagViewCount,
        RANK() OVER (ORDER BY SUM(p.Score) DESC, COUNT(p.Id) DESC) AS TagScoreRank,
        NTILE(10) OVER (ORDER BY COUNT(p.Id) DESC, SUM(p.Score) DESC) AS TagVolumeDecile
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= DATE '2020-01-01'
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 50
),
FinalPostTagUserAggregation AS (
    SELECT
        pdh.PostId,
        pdh.OwnerUserId,
        pdh.PostCreationDate,
        pdh.PostScore,
        pdh.ViewCount,
        pdh.AnswerCount,
        pdh.CommentCount,
        pdh.FavoriteCount,
        pdh.DisplayTitle,
        pdh.PostStatusClassifier,
        pdh.HasLinkedPosts,
        pdh.HasDuplicatePosts,
        pdh.EditCount,
        pdh.ModerationEventCount,
        LOWER(t) AS TagName,
        (SELECT COUNT(DISTINCT pl_out.RelatedPostId)
         FROM PostLinks pl_out
         WHERE pl_out.PostId = pdh.PostId
           AND pl_out.LinkTypeId = 1
           AND pl_out.CreationDate > (pdh.PostCreationDate - INTERVAL '1 year')
        ) AS OutgoingLinksCount,
        (SELECT COUNT(DISTINCT pl_in.PostId)
         FROM PostLinks pl_in
         WHERE pl_in.RelatedPostId = pdh.PostId
           AND pl_in.LinkTypeId = 1
           AND pl_in.CreationDate > (pdh.PostCreationDate - INTERVAL '6 months')
        ) AS IncomingLinksCount,
        LAG(pdh.PostScore, 1, 0) OVER (PARTITION BY pdh.OwnerUserId ORDER BY pdh.PostCreationDate) AS PreviousPostScore,
        LEAD(pdh.PostScore, 1, 0) OVER (PARTITION BY pdh.OwnerUserId ORDER BY pdh.PostCreationDate) AS NextPostScore,
        AVG(pdh.PostScore) OVER (PARTITION BY pdh.OwnerUserId, EXTRACT(YEAR FROM pdh.PostCreationDate)) AS UserYearlyAvgPostScore
    FROM PostDetailsWithHistory pdh,
         LATERAL (
             SELECT unnest(pdh.TagArray) AS t
         ) AS tag_exp
    WHERE pdh.rn_latest_history = 1
      AND pdh.PostTypeId IN (1, 2)
),
TopUsersScalar AS (
    SELECT COUNT(DISTINCT UserId) AS cnt FROM UserEngagement WHERE Reputation > 50000
),
TopTagsScalar AS (
    SELECT COUNT(DISTINCT TagName) AS cnt FROM RankedTagPerformance WHERE TagScoreRank <= 10
),
HighActivityUsers AS (
    SELECT ph_sub.UserId
    FROM PostHistory ph_sub
    GROUP BY ph_sub.UserId
    HAVING COUNT(ph_sub.Id) > 1000
)
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.UserCreationDate,
    ue.TotalQuestions,
    ue.TotalAnswers,
    ue.TotalPostScore AS UserTotalPostScore,
    ue.TotalCommentScore AS UserTotalCommentScore,
    fpta.TagName,
    SUM(fpta.PostScore) AS TagContributionScore,
    COUNT(fpta.PostId) AS TaggedPostCount,
    AVG(fpta.ViewCount) AS AvgTaggedPostViews,
    AVG(fpta.AnswerCount) AS AvgTaggedPostAnswers,
    MAX(fpta.EditCount) AS MaxEditsOnUserPostsForTag,
    AVG(COALESCE(fpta.OutgoingLinksCount, 0) + COALESCE(fpta.IncomingLinksCount, 0)) AS AvgPostLinkActivity,
    RTP.TagScoreRank,
    RTP.TagVolumeDecile,
    CASE
        WHEN ue.Reputation > 50000 AND RTP.TagScoreRank <= 10 AND ue.TotalAnswers > ue.TotalQuestions * 1.5 THEN 'Elite Answer Specialist'
        WHEN ue.Reputation > 10000 AND RTP.TagScoreRank <= 50 AND ue.TotalQuestions > ue.TotalAnswers THEN 'High-Value Questioner'
        WHEN ue.Reputation > 5000 AND RTP.TagVolumeDecile <= 3 THEN 'Active Niche Contributor'
        ELSE 'General Contributor'
    END AS UserTagProfileCategory,
    COALESCE(
        (SELECT AVG(q_sub.Score)
         FROM Posts q_sub
         WHERE q_sub.OwnerUserId = ue.UserId
           AND q_sub.PostTypeId = 1
           AND q_sub.AcceptedAnswerId IS NOT NULL
           AND char_length(COALESCE(q_sub.Title, q_sub.Body)) > 20
        ), 0.0
    ) AS AvgScoreAcceptedQuestions,
    SUM(CASE WHEN fpta.PostStatusClassifier = 'Accepted' THEN 1 ELSE 0 END) AS AcceptedAnswersCount,
    SUM(CASE WHEN fpta.PostStatusClassifier = 'Closed' THEN 1 ELSE 0 END) AS ClosedPostsCount,
    SUM(CASE WHEN COALESCE(fpta.ModerationEventCount, 0) <> 0 THEN 1 ELSE 0 END) AS PostsWithModerationEvents,
    SUM(COALESCE(fpta.PostScore - fpta.PreviousPostScore, 0)) AS TotalScoreDiffFromPrevious,
    SUM(COALESCE(fpta.NextPostScore - fpta.PostScore, 0)) AS TotalScoreDiffToNext,
    AVG(fpta.UserYearlyAvgPostScore) AS OverallUserYearlyAvgPostScore,
    (SELECT cnt FROM TopUsersScalar) AS TopUsersCount,
    (SELECT cnt FROM TopTagsScalar) AS TopTagsCount,
    CASE WHEN ue.UserId IN (SELECT UserId FROM HighActivityUsers) AND ue.Reputation > 20000 THEN 'High Activity User' ELSE NULL END AS IsHighActivityPowerUser
FROM UserEngagement ue
FULL OUTER JOIN FinalPostTagUserAggregation fpta ON ue.UserId = fpta.OwnerUserId
LEFT JOIN RankedTagPerformance RTP ON fpta.TagName = LOWER(RTP.TagName)
WHERE
    fpta.TagName IS NOT NULL
    AND ue.UserId IS NOT NULL
    AND fpta.PostCreationDate BETWEEN DATE '2020-01-01' AND DATE '2023-12-31'
    AND fpta.EditCount >= 1
    AND (fpta.ModerationEventCount IS NULL OR fpta.ModerationEventCount <= 5)
    AND char_length(COALESCE(fpta.DisplayTitle, '')) >= 10
GROUP BY
    ue.UserId, ue.DisplayName, ue.Reputation, ue.UserCreationDate, ue.TotalQuestions, ue.TotalAnswers,
    ue.TotalPostScore, ue.TotalCommentScore, fpta.TagName, RTP.TagScoreRank, RTP.TagVolumeDecile
HAVING
    COUNT(fpta.PostId) > 5
    AND SUM(fpta.PostScore) > 10
    AND AVG(fpta.PreviousPostScore) IS NOT NULL
ORDER BY
    ue.Reputation DESC, TagContributionScore DESC, TaggedPostCount DESC
LIMIT 500;