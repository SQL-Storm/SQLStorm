WITH BasePosts AS (
    SELECT
        p.Id,
        p.Title,
        p.Score,
        p.AnswerCount,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        CASE WHEN p.Score > 0 THEN TRUE ELSE FALSE END AS HasPositiveScore,
        p.PostTypeId
    FROM Posts p
    WHERE p.PostTypeId = 1
),
TopScore AS (
    SELECT
        Id,
        Title,
        Score,
        AnswerCount,
        ViewCount,
        Tags,
        OwnerUserId,
        HasPositiveScore,
        PostTypeId,
        RANK() OVER (ORDER BY Score DESC) AS RankScore
    FROM BasePosts
    WHERE Score > 100
    ORDER BY Score DESC
    LIMIT 10
),
TopViews AS (
    SELECT
        Id,
        Title,
        Score,
        AnswerCount,
        ViewCount,
        Tags,
        OwnerUserId,
        HasPositiveScore,
        PostTypeId,
        RANK() OVER (ORDER BY ViewCount DESC) AS RankViews
    FROM BasePosts
    WHERE ViewCount > 1000
    ORDER BY ViewCount DESC
    LIMIT 10
),
Combined AS (
    SELECT Id, Title, Score, AnswerCount, ViewCount, Tags, OwnerUserId, HasPositiveScore, PostTypeId FROM TopScore
    UNION ALL
    SELECT Id, Title, Score, AnswerCount, ViewCount, Tags, OwnerUserId, HasPositiveScore, PostTypeId FROM TopViews
),
EditStats AS (
    SELECT
        ph.PostId,
        COUNT(*) AS EditCount
    FROM PostHistory ph
    GROUP BY ph.PostId
),
UserStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUp,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDown,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName
)
SELECT
    us.UserId,
    us.DisplayName,
    c.Id          AS PostId,
    c.Title,
    COALESCE(es.EditCount, 0) AS EditHistory,
    CASE WHEN c.HasPositiveScore THEN 'Positive' ELSE 'Non-positive' END AS ScoreFlag,
    (SELECT COUNT(*) FROM Comments com WHERE com.PostId = c.Id) AS CommentCount,
    us.QuestionCount,
    us.AnswerCount,
    us.TotalUp - us.TotalDown AS ReputationDelta,
    ROW_NUMBER() OVER (PARTITION BY us.UserId ORDER BY c.Score DESC) AS PostRank
FROM Combined c
LEFT JOIN EditStats es ON es.PostId = c.Id
JOIN UserStats us ON us.UserId = c.OwnerUserId
WHERE (es.EditCount IS NULL OR es.EditCount < 5)
  AND (c.Tags IS NULL OR LOWER(c.Tags) NOT LIKE '%java%')
  AND us.QuestionCount > 0
GROUP BY
    us.UserId,
    us.DisplayName,
    c.Id,
    c.Title,
    es.EditCount,
    c.HasPositiveScore,
    c.Score,
    c.OwnerUserId,
    c.Tags,
    us.QuestionCount,
    us.AnswerCount,
    us.TotalUp,
    us.TotalDown
ORDER BY us.TotalUp - us.TotalDown DESC,
         c.Score DESC
LIMIT 200;