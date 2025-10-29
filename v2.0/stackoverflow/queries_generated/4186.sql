-- {"query": "4186.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1344} 

WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        u.DisplayName AS EditorDisplayName,
        ph.CreationDate AS EditDate,
        ph.PostHistoryTypeId,
        pht.Name AS EditTypeName,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
PostEditSummaries AS (
    SELECT
        rpe.PostId,
        rpe.EditorDisplayName,
        rpe.EditDate,
        SUM(CASE WHEN rpe.PostHistoryTypeId = 4 THEN 1 ELSE 0 END) AS TitleEdits,
        SUM(CASE WHEN rpe.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS BodyEdits,
        SUM(CASE WHEN rpe.PostHistoryTypeId = 6 THEN 1 ELSE 0 END) AS TagEdits,
        COUNT(*) AS TotalEdits
    FROM RankedPostEdits rpe
    WHERE rpe.rn <= 3 -- Consider the top 3 edits for each post
    GROUP BY rpe.PostId, rpe.EditorDisplayName, rpe.EditDate
),
UserContribution AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserDisplayName,
        COUNT(DISTINCT p.Id) AS QuestionsAnswered,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersPosted,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        COUNT(DISTINCT b.Id) AS BadgesEarned,
        SUM(p.Score) AS TotalPostScore,
        MAX(u.Reputation) AS MaxReputation
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
RecentActivity AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        p.LastActivityDate,
        ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC) as ActivityRank
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Only consider questions
),
CommunityEngagement AS (
    SELECT
        p.Id AS PostId,
        COUNT(DISTINCT c.Id) AS CommentCountOnPost,
        SUM(CASE WHEN c.Score > 5 THEN 1 ELSE 0 END) AS HighScoringComments,
        p.AnswerCount,
        p.FavoriteCount,
        COALESCE(p.ViewCount, 0) AS PostViewCount,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwned
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.AnswerCount, p.FavoriteCount, p.ViewCount, p.ClosedDate, p.CommunityOwnedDate
)
SELECT
    ra.PostId,
    ra.Title,
    ra.PostCreationDate,
    ra.LastActivityDate,
    pes.EditorDisplayName,
    pes.TitleEdits,
    pes.BodyEdits,
    pes.TagEdits,
    pes.TotalEdits,
    COALESCE(uc.UserDisplayName, 'Unknown') AS OwnerDisplayName,
    uc.QuestionsAnswered,
    uc.AnswersPosted,
    uc.QuestionsAsked,
    uc.BadgesEarned,
    uc.TotalPostScore,
    uc.MaxReputation,
    ce.CommentCountOnPost,
    ce.HighScoringComments,
    ce.AnswerCount,
    ce.FavoriteCount,
    ce.PostViewCount,
    ce.IsClosed,
    ce.IsCommunityOwned,
    CASE
        WHEN ce.PostViewCount > 100000 AND ce.AnswerCount > 50 AND ce.HighScoringComments > 5 THEN 'Highly Engaged'
        WHEN ce.PostViewCount > 50000 AND ce.AnswerCount > 20 THEN 'Moderately Engaged'
        WHEN ce.IsClosed = 1 THEN 'Closed'
        ELSE 'Standard'
    END AS EngagementLevel,
    CASE
        WHEN uc.BadgesEarned > 10 AND uc.MaxReputation > 50000 THEN 'Experienced Contributor'
        WHEN uc.BadgesEarned > 5 AND uc.MaxReputation > 10000 THEN 'Active Contributor'
        ELSE 'New Contributor'
    END AS ContributorTier
FROM RecentActivity ra
LEFT JOIN PostEditSummaries pes ON ra.PostId = pes.PostId
LEFT JOIN Posts p_owner ON ra.PostId = p_owner.Id -- Join Posts again to get OwnerUserId for UserContribution
LEFT JOIN UserContribution uc ON p_owner.OwnerUserId = uc.UserId
LEFT JOIN CommunityEngagement ce ON ra.PostId = ce.PostId
WHERE ra.ActivityRank <= 1000 -- Focus on the top 1000 most recently active questions
AND (pes.TotalEdits IS NULL OR pes.TotalEdits > 0) -- Only include posts that have been edited, or where edit info is null
AND uc.UserId IS NOT NULL -- Ensure we have user contribution data
ORDER BY ra.LastActivityDate DESC;
