-- {"query": "5669.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 694} 
WITH
ActiveQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.LastActivityDate,
        p.FavoriteCount,
        p.ContentLicense
    FROM Posts p
    WHERE p.PostTypeId = 1
),
RecentActivity AS (
    SELECT
        aq.QuestionId,
        aq.Title,
        aq.CreationDate,
        aq.OwnerUserId,
        aq.Score,
        aq.ViewCount,
        aq.Tags,
        aq.AnswerCount,
        aq.CommentCount,
        aq.LastActivityDate,
        aq.FavoriteCount,
        aq.ContentLicense,
        -- correlated subquery: latest active edit by LastEditor
        (SELECT MAX(ph.CreationDate)
         FROM PostHistory ph
         WHERE ph.PostId = aq.QuestionId
           AND ph.PostHistoryTypeId IN (4,5,6,10,11,16,24,36)
        ) AS LastEditDate
    FROM ActiveQuestions aq
),
TopTags AS (
    SELECT
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId
    FROM Tags t
    WHERE t.IsModeratorOnly = 0
),
Enriched AS (
    SELECT
        ra.QuestionId,
        ra.Title,
        ra.CreationDate,
        ra.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation,
        ra.Score,
        ra.ViewCount,
        ra.AnswerCount,
        ra.CommentCount,
        ra.LastActivityDate,
        ra.FavoriteCount,
        ra.ContentLicense,
        ra.LastEditDate,
        tt.TagName
    FROM RecentActivity ra
    LEFT JOIN Users u ON ra.OwnerUserId = u.Id
    LEFT JOIN LATERAL (
        SELECT unnest(string_to_array(substr(ra.Tags, 2, length(ra.Tags)-2), '><')) AS TagName
    ) AS tt ON true
    -- Note: above assumes PostgreSQL; for SQL Server/MySQL adjust tag parsing accordingly
),
ComplexStats AS (
    SELECT
        e.QuestionId,
        e.Title,
        e.OwnerUserId,
        e.OwnerDisplayName,
        e.Reputation,
        e.Score,
        e.ViewCount,
        e.AnswerCount,
        e.CommentCount,
        e.LastActivityDate,
        e.FavoriteCount,
        e.ContentLicense,
        e.LastEditDate,
        e.TagName,
        -- window function: rank questions by last activity per day
        DENSE_RANK() OVER (PARTITION BY CAST(e.LastActivityDate AS DATE)
                         ORDER BY e.LastActivityDate DESC, e.Score DESC) AS ActivityRank
    FROM Enriched e
)
SELECT
    cs.QuestionId,
    cs.Title,
    cs.OwnerDisplayName,
    cs.Reputation,
    cs.Score,
    cs.ViewCount,
    cs.AnswerCount,
    cs.CommentCount,
    cs.LastActivityDate,
    cs.LastEditDate,
    cs.TagName,
    cs.ActivityRank
FROM ComplexStats cs
WHERE cs.ActivityRank <= 10
ORDER BY cs.LastActivityDate DESC, cs.Score DESC
LIMIT 100;