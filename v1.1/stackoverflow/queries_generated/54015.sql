-- {"query": "54015.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 3530} 

/* ---------------------------------------------------------
   Benchmark query – heavy cross‑joins, window functions, 
   aggregates and JSON extraction. No external schema changes
   required.
   --------------------------------------------------------- */

WITH
-- 1️⃣  Gather core post statistics
post_stats AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Tags,
        p.CreationDate,
        p.LastActivityDate,
        p.AcceptedAnswerId,
        u.Reputation,
        u.Views AS UserViews,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
        COUNT(ph.Id) AS EditCount,
        COUNT(pl.Id) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateLinks,
        COUNT(pl.Id) FILTER (WHERE pl.LinkTypeId = 1) AS RelatedLinks
    FROM Posts p
    JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id
    WHERE p.PostTypeId = 1                 -- only questions
    GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount,
             p.AnswerCount, p.FavoriteCount,
             p.Tags, p.CreationDate, p.LastActivityDate,
             p.AcceptedAnswerId, u.Reputation, u.Views
),

-- 2️⃣  Extract tags safely (remove < and >, split)
tag_list AS (
    SELECT
        ps.Id,
        TRIM(BOTH '<>' FROM t.tag) AS TagName
    FROM post_stats ps
    CROSS JOIN LATERAL
        regexp_split_to_table(
            NULLIF(ps.Tags, ''),
            '\\>\\<'
        ) AS t(tag)
),

-- 3️⃣  Count tag occurrences per user
tag_user_counts AS (
    SELECT
        ps.OwnerUserId,
        t.TagName,
        COUNT(*) AS TagCount
    FROM post_stats ps
    JOIN tag_list t ON t.Id = ps.Id
    GROUP BY ps.OwnerUserId, t.TagName
),

-- 4️⃣  Per‑user aggregates (last 100k posts rate)
user_metrics AS (
    SELECT
        ps.OwnerUserId,
        u.DisplayName,
        u.Reputation,
        u.LastAccessDate,
        COUNT(ps.Id) AS QuestionCount,
        AVG(ps.Score) AS AvgScore,
        STDDEV(ps.Score) AS ScoreStdDev,
        AVG(ps.ViewCount) AS AvgViews,
        SUM(ps.AnswerCount) AS TotalAnswers,
        MAX(ps.AnswerCount) AS MaxAnswers,
        MIN(ps.AnswerCount) AS MinAnswers,
        MAX(ps.FavoriteCount) AS MaxFavorites,
        SUM(ps.UpVotes) AS TotalUpVotes,
        SUM(ps.DownVotes) AS TotalDownVotes,
        AVG(ps.EditCount) AS AvgEditCount,
        SUM(ps.DuplicateLinks) AS TotalDuplicateLinks,
        SUM(ps.RelatedLinks) AS TotalRelatedLinks,
        SUM(tuc.TagCount) AS TotalTagOccurrences,
        MAX(ps.CreationDate) AS LatestPost
    FROM post_stats ps
    JOIN Users u ON u.Id = ps.OwnerUserId
    LEFT JOIN tag_user_counts tuc ON tuc.OwnerUserId = ps.OwnerUserId
    GROUP BY ps.OwnerUserId, u.DisplayName, u.Reputation, u.LastAccessDate
),

-- 5️⃣  Create a JSON blob per user for tag stats
user_tag_json AS (
    SELECT
        tuc.OwnerUserId,
        json_agg(json_build_object(
            'Tag', tuc.TagName,
            'Count', tuc.TagCount
        ) ORDER BY tuc.TagCount DESC) AS TagStats
    FROM tag_user_counts tuc
    GROUP BY tuc.OwnerUserId
)

-- ---------------------------------------------------------
-- Final result – users ordered by activity and quality
-- ---------------------------------------------------------
SELECT
    um.OwnerUserId AS UserId,
    um.DisplayName,
    um.Reputation,
    um.LastAccessDate,
    um.QuestionCount,
    um.AvgScore,
    um.ScoreStdDev,
    um.AvgViews,
    um.TotalAnswers,
    um.MaxAnswers,
    um.MinAnswers,
    um.MaxFavorites,
    um.TotalUpVotes,
    um.TotalDownVotes,
    um.AvgEditCount,
    um.TotalDuplicateLinks,
    um.TotalRelatedLinks,
    um.TotalTagOccurrences,
    utj.TagStats,
    um.LatestPost
FROM user_metrics um
LEFT JOIN user_tag_json utj ON utj.OwnerUserId = um.OwnerUserId
ORDER BY
    um.QuestionCount DESC,
    um.AvgScore DESC,
    um.Reputation DESC
LIMIT 500;
