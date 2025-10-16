-- {"query": "27010.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 1168} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(p.Id) AS TotalPosts,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS TotalQuestions,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalAnswers,
        COALESCE(MAX(p.Score), 0) AS MaxPostScore,
        COALESCE(AVG(p.Score), 0) AS AvgPostScore,
        LAST_VALUE(p.LastActivityDate) OVER (PARTITION BY u.Id ORDER BY p.LastActivityDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS LastPostActivityDate
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY
        u.Id, u.Reputation, u.CreationDate
),

HighReputationUsers AS (
    SELECT
        UserId,
        Reputation,
        UserCreationDate,
        TotalPosts,
        TotalQuestions,
        TotalAnswers,
        MaxPostScore,
        AvgPostScore,
        LastPostActivityDate
    FROM
        UserActivity
    WHERE
        Reputation > 10000
),

RecentPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.LastActivityDate,
        u.DisplayName AS OwnerDisplayName,
        ph.PostHistoryTypeId,
        ph.CreationDate AS PostHistoryDate,
        ph.UserId AS EditorUserId,
        ph.Comment AS PostHistoryComment,
        COALESCE(c.Id, 0) AS CommentCountFromCommentsTable
    FROM
        Posts p
    LEFT JOIN
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN
        PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    WHERE
        p.CreationDate > DATE_SUB(NOW(), INTERVAL 30 DAY)
),

TopTags AS (
    SELECT
        t.TagName,
        t.Count,
        COALESCE( subscription.excerpt,NULL) AS ExcerptPostId,
        COALESCE(wiki.Id, NULL) AS WikiPostId
    FROM
        Tags t
    LEFT JOIN
        Posts excerpt ON excerpt.Id = t.ExcerptPostId
    LEFT JOIN
        Posts wiki ON wiki.Id = t.WikiPostId
    WHERE
        t.Count > 1000
    ORDER BY
        t.Count DESC
    LIMIT 10
)

SELECT
    hru.UserId,
    hru.Reputation,
    hru.UserCreationDate,
    hru.TotalPosts,
    hru.TotalQuestions,
    hru.TotalAnswers,
    hru.MaxPostScore,
    hru.AvgPostScore,
    hru.LastPostActivityDate,
    rp.PostId,
    rp.PostTypeId,
    rp.PostCreationDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerUserId,
    rp.Title,
    rp.Tags,
    rp.AnswerCount,
    rp.CommentCount,
    rp.LastActivityDate,
    rp.OwnerDisplayName,
    rp.PostHistoryTypeId,
    rp.PostHistoryDate,
    rp.EditorUserId,
    rp.PostHistoryComment,
    rp.CommentCountFromCommentsTable,
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId
FROM
    HighReputationUsers hru
LEFT JOIN
    RecentPosts rp ON hru.UserId = rp.OwnerUserId
LEFT JOIN TopTags t
    on(rp.Tags like  (CONCAT('%<', t.TagName, '>%')) AS TestTags)
ORDER BY
    hru.Reputation DESC,
    rp.Score DESC,
    t.Count DESC
LIMIT 50;
