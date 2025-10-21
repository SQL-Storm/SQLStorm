-- {"query": "18045.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1554} 

WITH PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        pt.Name AS PostType,
        COALESCE(p.Score, 0) AS PostScore,
        COALESCE(p.ViewCount, 0) AS PostViewCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        u.Reputation AS OwnerReputation,
        u.CreationDate AS OwnerCreationDate,
        (
            SELECT COUNT(c.Id)
            FROM Comments c
            WHERE c.PostId = p.Id AND c.CreationDate BETWEEN p.CreationDate AND p.LastActivityDate
        ) AS CommentCountWithinPostLife,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS PostSequenceForUser
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.OwnerUserId IS NOT NULL AND pt.Name IN ('Question', 'Answer')
),
UserActivitySummary AS (
    SELECT
        pa.OwnerUserId,
        COUNT(DISTINCT pa.PostId) AS TotalPosts,
        SUM(pa.PostScore) AS TotalScoreGained,
        AVG(pa.PostViewCount) AS AvgPostViews,
        MAX(pa.PostCreationDate) AS LastPostDate,
        COUNT(CASE WHEN pa.PostType = 'Question' THEN pa.PostId ELSE NULL END) AS QuestionsAsked,
        COUNT(CASE WHEN pa.PostType = 'Answer' THEN pa.PostId ELSE NULL END) AS AnswersGiven,
        SUM(CASE WHEN pa.PostType = 'Question' THEN pa.AnswerCount ELSE 0 END) AS TotalAnswersToQuestions,
        COUNT(CASE WHEN pa.PostSequenceForUser = 1 THEN pa.PostId ELSE NULL END) AS IsMostRecentPost
    FROM PostEngagement pa
    GROUP BY pa.OwnerUserId
),
PostInteraction AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.Id ELSE NULL END) AS BodyEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 4 THEN ph.Id ELSE NULL END) AS TitleEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id ELSE NULL END) AS CloseEvents,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 12 THEN ph.Id ELSE NULL END) AS DeleteEvents,
        MAX(CASE WHEN ph.PostHistoryTypeId = 19 THEN ph.CreationDate ELSE NULL END) AS LastProtectionDate,
        COUNT(DISTINCT ph.UserId) AS DistinctEditors
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 10, 12, 19)
    GROUP BY ph.PostId
),
UserVoting AS (
    SELECT
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN v.Id ELSE NULL END) AS UpVotesGiven,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN v.Id ELSE NULL END) AS DownVotesGiven,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN v.Id ELSE NULL END) AS FavoriteVotesGiven
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3, 5)
    GROUP BY v.UserId
)
SELECT
    pe.PostId,
    pe.Title,
    pe.PostType,
    pe.PostScore,
    pe.PostViewCount,
    pe.AnswerCount,
    pe.CommentCount,
    pe.FavoriteCount,
    pe.OwnerReputation,
    pe.OwnerCreationDate,
    pi.BodyEdits,
    pi.TitleEdits,
    pi.CloseEvents,
    pi.DeleteEvents,
    pi.LastProtectionDate,
    pi.DistinctEditors,
    COALESCE(uv.UpVotesGiven, 0) AS UserUpVotesGiven,
    COALESCE(uv.DownVotesGiven, 0) AS UserDownVotesGiven,
    COALESCE(uas.TotalPosts, 0) AS UserTotalPosts,
    COALESCE(uas.TotalScoreGained, 0) AS UserTotalScoreGained,
    uas.AvgPostViews AS UserAvgPostViews,
    uas.QuestionsAsked AS UserQuestionsAsked,
    uas.AnswersGiven AS UserAnswersGiven,
    uas.TotalAnswersToQuestions AS UserTotalAnswersToQuestions,
    CASE
        WHEN pe.PostSequenceForUser = 1 AND uas.IsMostRecentPost = 1 THEN 'Most Recent and Highest Sequence'
        WHEN pe.PostSequenceForUser = 1 THEN 'Most Recent for User'
        ELSE 'Other'
    END AS PostSequenceStatus,
    CASE
        WHEN pe.PostCreationDate < DATE_SUB(NOW(), INTERVAL 1 YEAR) THEN 'Older Than 1 Year'
        WHEN pe.PostCreationDate >= DATE_SUB(NOW(), INTERVAL 1 YEAR) AND pe.PostCreationDate < NOW() THEN 'Within 1 Year'
        ELSE 'Future Post'
    END AS PostAgeCategory,
    LOWER(SUBSTRING(pe.Title, 1, 3)) AS TitlePrefix,
    CASE WHEN pe.OwnerUserId IS NULL THEN 'Anonymous' WHEN pe.OwnerReputation > 50000 THEN 'High Reputation' ELSE 'Standard Reputation' END AS OwnerStatus,
    pe.CommentCountWithinPostLife,
    (pe.PostScore + pe.AnswerCount + pe.CommentCount) AS TotalEngagementScore,
    IIF(pe.PostScore > 100, 'Popular', 'Standard') AS PopularityLevel,
    CASE WHEN pi.LastProtectionDate IS NOT NULL THEN 1 ELSE 0 END AS IsProtected,
    CASE WHEN pe.OwnerUserId = 1 THEN 'Community User' ELSE 'Regular User' END AS OwnerType
FROM PostEngagement pe
LEFT JOIN PostInteraction pi ON pe.PostId = pi.PostId
LEFT JOIN UserVoting uv ON pe.OwnerUserId = uv.UserId
LEFT JOIN UserActivitySummary uas ON pe.OwnerUserId = uas.OwnerUserId
WHERE pe.PostScore > -10
  AND (pe.Title LIKE '%SQL%' OR pe.Title LIKE '%Database%')
  AND pe.OwnerReputation > 1000
  AND pe.CommentCountWithinPostLife BETWEEN 5 AND 50
ORDER BY pe.PostScore DESC, pe.PostViewCount DESC
LIMIT 100;
