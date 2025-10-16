-- {"query": "1501.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1322} 

WITH RecursiveUserBadgeRanks AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        b.Class,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY b.Date DESC, b.Name) AS RecentBadgeRank
    FROM
        Users u
        LEFT JOIN Badges b ON b.UserId = u.Id AND b.Date IS NOT NULL
),
TopUserBadges AS (
    SELECT UserId,
           STRING_AGG(CONCAT(Class,
                             '-', REPLACE(Name, ' ', '_')),
                      ',' ORDER BY Class, Name) AS BadgeSummary
    FROM Badges
    GROUP BY UserId
),
HighActivityPosts AS (
    SELECT
        p.Id as PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.ParentId,
        p.AcceptedAnswerId,
        p.Title,
        p.CreationDate,
        p.Score,
        COALESCE(p.ViewCount, 0) AS ViewCount,
        p.Tags,
        (vc.TotalVoteScore + COALESCE(MyVotes.VoteScore, 0)) AS WeightedVotes,
        -- Complex expression for engagement: weighted combination of score, views, age weight (deprecated constant + days alive comp)
        (
            (p.Score * 3)
            + COALESCE(ViewCount * 0.01, 0)
            + LOG(1 + EXTRACT(EPOCH FROM age(now(), p.CreationDate))/86400) * CASE WHEN p.PostTypeId = 1 THEN 5 ELSE 3 END
            - 5 * CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END
        ) AS EngagementScore
    FROM Posts p
    LEFT JOIN (
        -- Aggregate votes per post grouped by type compensating some custom weighing including bounties
        SELECT PostId, 
               SUM(
                   CASE WHEN VoteTypeId = 2 THEN 1 -- UpMod
                        WHEN VoteTypeId = 3 THEN -1 -- DownMod
                        WHEN VoteTypeId IN (8,9) THEN COALESCE(BountyAmount, 0)*2
                        ELSE 0 END
               ) AS TotalVoteScore
        FROM Votes
        GROUP BY PostId
    ) vc ON vc.PostId = p.Id
    LEFT JOIN (
        -- Current user's specific votes within posts (simulate user id 42 for correlated support—note for bench test provide runUploader = 42__)
        SELECT DISTINCT VoteTypeId, PostId, (CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS VoteScore
        FROM Votes
        WHERE UserId = 42
    ) MyVotes ON MyVotes.PostId = p.Id            
    WHERE p.Score IS NOT NULL
),
AnswersWithScoreRank AS (
    SELECT
        ans.Id AS AnswerId,
        ans.ParentId,
        ans.OwnerUserId,
        ans.Score,
        ans.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY ans.ParentId ORDER BY ans.Score DESC, ans.CreationDate ASC) AS AnswerRankByScore,
        COUNT(*) OVER (PARTITION BY ans.ParentId) AS AnswersCount
    FROM Posts ans
    WHERE ans.PostTypeId = 2
),
QuestionCloseStats AS (
    SELECT ch.PostId, 
           COUNT(CASE WHEN ch.PostHistoryTypeId IN (10, 12) THEN 1 ELSE NULL END) AS CloseOrDeletedVotes,
           MAX(CASE WHEN ch.PostHistoryTypeId = 10 THEN ch.Comment END) AS LastCloseReasonCode,
           COUNT(DISTINCT ch.UserId) AS UniqueVotersCount,
           STRING_AGG(DISTINCT crt.Name, ', ') AS CloseReasonsUsed
    FROM PostHistory ch
    LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(ch.Comment AS INT) AND ch.PostHistoryTypeId = 10
    GROUP BY ch.PostId        
),
UserLocationSimilarity AS (
    SELECT u1.Id AS UserId1, u2.Id AS UserId2,
           CASE
               WHEN u1.Location IS NOT NULL AND u2.Location IS NOT NULL THEN
                    (LENGTH(u1.Location) + LENGTH(u2.Location)) - LENGTH(REPLACE(LOWER(u1.Location), LOWER(u2.Location), ''))
               ELSE NULL END AS LocationSubstrOverlap
    FROM Users u1
    JOIN Users u2 ON u1.Id <> u2.Id AND u1.Reputation > u2.Reputation
),
MergedTagsForPopularPosts AS (
    SELECT DISTINCT UNNEST(string_to_array(REPLACE(REPLACE(tg.T, '><', ','), '<', ''), ',')) AS IndividualTag,
           t.Count AS TagCount
    FROM (
        SELECT p.Tags AS T
        FROM Posts p
        WHERE p.Score >= 50 AND p.Tags IS NOT NULL
        LIMIT 500
    ) tg
    JOIN Tags t ON t.TagName = UNNEST(string_to_array(REPLACE(REPLACE(tg.T, '><', ','), '<', ''), ','))
)
SELECT 
    p.PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.EngagementScore,
    qcs.CloseOrDeletedVotes,
    qcs.CloseReasonsUsed,
    au.AnswerRankByScore,
    au.AnswersCount,
    tng.IndividualTag,
    tut.BadgeSummary,
    COALESCE(locSim.LocationSubstrOverlap, 0) AS LocationSimilarityScore,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.EngagementScore DESC) AS PostTypeEngagementPosition
FROM HighActivityPosts p
LEFT JOIN QuestionCloseStats qcs ON qcs.PostId = p.PostId
LEFT JOIN AnswersWithScoreRank au ON au.ParentId = p.PostId AND au.AnswerRankByScore = 1
LEFT JOIN TopUserBadges tut ON tut.UserId = p.OwnerUserId
LEFT JOIN UserLocationSimilarity locSim ON locSim.UserId1 = p.OwnerUserId
LEFT JOIN MergedTagsForPopularPosts tng ON '<' || tng.IndividualTag || '>' LIKE '%' || p.Tags || '%'
WHERE p.PostTypeId IN (1, 2)
  AND p.EngagementScore > 10
ORDER BY p.EngagementScore DESC
FETCH FIRST 50 ROWS ONLY;
