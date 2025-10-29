-- {"query": "4524.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1247}
WITH RECURSIVE PostHierarchy AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        p.Title,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate) AS rn,
        p.Tags
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ParentId IS NULL

    UNION ALL

    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        0 AS AnswerCount,
        p.Title,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate) AS rn,
        p.Tags
    FROM Posts p
    INNER JOIN PostHierarchy ph ON p.ParentId = ph.Id
    WHERE p.PostTypeId = 2
),
UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(p.ViewCount) AS AverageViewCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount,
        RANK() OVER (PARTITION BY DATE_TRUNC('month', u.CreationDate) ORDER BY u.Reputation DESC) AS ReputationRankOfMonth
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.CreationDate, u.Reputation
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId IN (2, 3) THEN (CASE v.VoteTypeId WHEN 2 THEN 1 WHEN 3 THEN -1 END) ELSE 0 END), 0) AS NetVoteScore,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 'CLOSED' ELSE 'OPEN' END AS PostStatus,
        SUM(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningScore
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id, p.ClosedDate, p.OwnerUserId, p.CreationDate, p.Score
)
SELECT
    ph.Id AS PostId,
    pt.Name AS PostTypeName,
    ups.DisplayName AS OwnerDisplayName,
    EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - ph.CreationDate)) + (ph.Score * 0.01) + (ph.AnswerCount * 0.1) AS WeightedPostAge,
    ups.QuestionCount,
    ups.AnswerCount AS UserAnswerCount,
    ups.TotalScore AS UserTotalScore,
    ups.LastPostDate,
    ups.AverageViewCount,
    ups.BadgeCount,
    ups.ReputationRankOfMonth,
    pe.CommentCount,
    pe.UpVoteCount,
    pe.DownVoteCount,
    pe.PostStatus,
    pe.RunningScore,
    (SELECT CASE
         WHEN p2.Score > 1000 THEN 'HIGH_SCORE'
         WHEN p3.ClosedDate IS NOT NULL THEN 'CLOSED_POST'
         ELSE NULL
     END
     FROM Posts p2
     LEFT JOIN Posts p3 ON p3.Id = p2.Id
     WHERE p2.Id = ph.Id
     LIMIT 1) AS PostClassification,
    (SELECT STRING_AGG(tag, ', ') FROM (
         SELECT tag FROM (
             SELECT
                 CASE
                     WHEN TRIM(value) = '' THEN NULL
                     ELSE TRIM(value)
                 END AS tag
             FROM (
                 SELECT
                     CASE
                         WHEN ph.Tags IS NULL OR ph.Tags = '' THEN NULL
                         ELSE COALESCE(NULLIF(REPLACE(REPLACE(ph.Tags, '><', '|'), '<', ''), ''), ph.Tags)
                     END AS tag_flat
             ) tf
             CROSS JOIN LATERAL (
                 SELECT regexp_split_to_table(tf.tag_flat, E'\\|') AS value
             ) split_vals
         ) extracted
         WHERE tag IS NOT NULL
    ) t) AS FormattedTags
FROM PostHierarchy ph
JOIN PostTypes pt ON ph.PostTypeId = pt.Id
LEFT JOIN UserPostStats ups ON ph.OwnerUserId = ups.UserId
LEFT JOIN PostEngagement pe ON ph.Id = pe.PostId
WHERE ph.rn BETWEEN 100 AND 200
GROUP BY
    ph.Id,
    pt.Name,
    ups.DisplayName,
    EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - ph.CreationDate)),
    ph.Score,
    ph.AnswerCount,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.TotalScore,
    ups.LastPostDate,
    ups.AverageViewCount,
    ups.BadgeCount,
    ups.ReputationRankOfMonth,
    pe.CommentCount,
    pe.UpVoteCount,
    pe.DownVoteCount,
    pe.PostStatus,
    pe.RunningScore,
    ph.Tags,
    ph.CreationDate,
    ph.PostTypeId
ORDER BY ph.CreationDate DESC;