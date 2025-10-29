-- {"query": "2021.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1495}
WITH RecursiveUserBadgeStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        b.Class,
        COUNT(b.Id) AS BadgeCount,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY b.Class ASC, b.Date DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, b.Class, b.Date
), LatestPostEdits AS (
    SELECT ph.PostId, ph.UserId AS EditorUserId, ph.CreationDate AS EditDate,
           ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS EditRank
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9)
), PostWithLatestEdit AS (
    SELECT p.Id AS PostId, p.OwnerUserId, p.PostTypeId, p.Score, p.ViewCount, p.CreationDate,
           le.EditorUserId, le.EditDate,
           COALESCE(p.Title,
             CASE WHEN p.PostTypeId = 2 THEN 
               (SELECT q.Title FROM Posts q WHERE q.Id = p.ParentId)
               ELSE '(no title)'
             END) AS ResolvedTitle,
           COALESCE(p.Tags, '') AS Tags
    FROM Posts p
    LEFT JOIN LatestPostEdits le ON le.PostId = p.Id AND le.EditRank = 1
), UserPostStats AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.PostId END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.PostId END) AS AnswerCount,
        AVG(COALESCE(p.Score,0) * CASE WHEN p.PostTypeId IN (1,2) THEN 1 ELSE NULL END) AS AvgScore,
        SUM(COALESCE(p.ViewCount,0) * CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionViews,
        STRING_AGG(DISTINCT t.tag, ',' ORDER BY t.tag) AS DistinctTags
    FROM Users u
    LEFT JOIN PostWithLatestEdit p ON p.OwnerUserId = u.Id
    LEFT JOIN LATERAL (
        SELECT TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM token)) AS tag
        FROM UNNEST(STRING_TO_ARRAY(COALESCE(p.Tags, ''), '><')) AS token
    ) t ON TRUE
    GROUP BY u.Id
), PostLinkDetails AS (
    SELECT pl.PostId, pl.RelatedPostId, lt.Name AS LinkTypeName,
           ROW_NUMBER() OVER (PARTITION BY pl.PostId ORDER BY pl.CreationDate DESC) AS LinkRank
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY pl.PostId, pl.RelatedPostId, lt.Name, pl.CreationDate, pl.Id
), DuplicateQuestions AS (
    SELECT DISTINCT pl.PostId AS DuplicateQuestionId,
                    pl.RelatedPostId AS OriginalQuestionId
    FROM PostLinkDetails pl
    WHERE pl.LinkTypeName = 'Duplicate'
), UserVoteAggregates AS (
    SELECT
        v.UserId,
        v.VoteTypeId,
        COUNT(v.Id) AS VoteCount,
        SUM(COALESCE(v.BountyAmount,0)) AS TotalBounty,
        MIN(v.CreationDate) AS FirstVoteDate,
        MAX(v.CreationDate) AS LastVoteDate
    FROM Votes v
    GROUP BY v.UserId, v.VoteTypeId
), ComplexUserSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        us.QuestionCount,
        us.AnswerCount,
        us.AvgScore,
        us.TotalQuestionViews,
        us.DistinctTags,
        COALESCE(bgs.BadgeCount,0) AS TotalBadges,
        COALESCE(vup.VoteCount,0) AS UpVotesGiven,
        COALESCE(vdn.VoteCount,0) AS DownVotesGiven,
        CASE WHEN u.Location IS NOT NULL AND u.Location <> '' THEN TRUE ELSE FALSE END AS HasLocation,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, us.QuestionCount DESC) AS RankByReputation
    FROM Users u
    LEFT JOIN UserPostStats us ON us.UserId = u.Id
    LEFT JOIN (
        SELECT UserId, SUM(BadgeCount) AS BadgeCount FROM RecursiveUserBadgeStats WHERE BadgeRank <= 5 GROUP BY UserId
    ) bgs ON bgs.UserId = u.Id
    LEFT JOIN UserVoteAggregates vup ON vup.UserId = u.Id AND vup.VoteTypeId = 2
    LEFT JOIN UserVoteAggregates vdn ON vdn.UserId = u.Id AND vdn.VoteTypeId = 3
)
SELECT 
    cus.UserId,
    cus.DisplayName,
    cus.Reputation,
    cus.QuestionCount,
    cus.AnswerCount,
    ROUND(CAST(cus.AvgScore AS numeric), 2) AS AveragePostScore,
    cus.TotalQuestionViews,
    cus.DistinctTags,
    cus.TotalBadges,
    cus.UpVotesGiven,
    cus.DownVotesGiven,
    cus.HasLocation,
    cus.RankByReputation,
    pq.PostId AS PostId,
    pq.ResolvedTitle,
    pq.PostTypeId,
    pq.Score AS PostScore,
    pq.ViewCount AS PostViewCount,
    pq.CreationDate AS PostCreationDate,
    dq.OriginalQuestionId AS DuplicateOfQuestionId,
    COALESCE(pld.LinkTypeName, '') AS LinkTypeName,
    COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.PostId = pq.PostId), 0) AS CommentCount,
    COALESCE((SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.OwnerUserId = cus.UserId AND p2.PostTypeId = 2), 0) AS AvgAnswerScoreByUser,
    CASE 
        WHEN pq.Score >= 50 THEN 'High Score'
        WHEN pq.Score BETWEEN 20 AND 49 THEN 'Medium Score'
        WHEN pq.Score < 20 AND pq.Score >= 0 THEN 'Low Score'
        ELSE 'Negative Score'
    END AS PostScoreCategory,
    LENGTH(COALESCE(pq.Tags, '')) AS TagsLength,
    CASE 
        WHEN cus.HasLocation THEN 'With Location'
        ELSE 'No Location'
    END AS UserLocationStatus
FROM ComplexUserSummary cus
LEFT JOIN PostWithLatestEdit pq ON pq.OwnerUserId = cus.UserId
LEFT JOIN DuplicateQuestions dq ON dq.DuplicateQuestionId = pq.PostId
LEFT JOIN PostLinkDetails pld ON pld.PostId = pq.PostId AND pld.LinkRank = 1
WHERE cus.Reputation > 1000
  AND (pq.PostTypeId = 1 OR pq.PostTypeId = 2)
  AND (pq.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '2' YEAR) OR pq.CreationDate IS NULL)
GROUP BY
    cus.UserId,
    cus.DisplayName,
    cus.Reputation,
    cus.QuestionCount,
    cus.AnswerCount,
    cus.AvgScore,
    cus.TotalQuestionViews,
    cus.DistinctTags,
    cus.TotalBadges,
    cus.UpVotesGiven,
    cus.DownVotesGiven,
    cus.HasLocation,
    cus.RankByReputation,
    pq.PostId,
    pq.ResolvedTitle,
    pq.PostTypeId,
    pq.Score,
    pq.ViewCount,
    pq.CreationDate,
    dq.OriginalQuestionId,
    pld.LinkTypeName,
    pq.Tags
ORDER BY cus.Reputation DESC, cus.QuestionCount DESC, pq.Score DESC
LIMIT 100;