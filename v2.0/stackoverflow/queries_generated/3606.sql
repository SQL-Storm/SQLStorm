-- {"query": "3606.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2720} 

WITH q AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        p.Score               AS QuestionScore,
        COALESCE(p.FavoriteCount,0) AS Favorites,
        COALESCE(p.ViewCount,0)    AS Views,
        COALESCE(p.AnswerCount,0)  AS AnswerCount,
        p.ClosedDate,
        p.CommunityOwnedDate
    FROM Posts p
    WHERE p.PostTypeId = 1                         -- questions
      AND p.CreationDate >= (CURRENT_DATE - INTERVAL '1 year')
),
ans AS (
    SELECT
        a.ParentId                               AS QuestionId,
        COUNT(*)                                 AS TotalAnswers,
        COUNT(*) FILTER (WHERE a.Score > 0)      AS PositiveAnswers,
        COUNT(*) FILTER (WHERE a.Score <= 0)     AS NonPositiveAnswers,
        MAX(a.Score)                             AS MaxAnswerScore,
        MIN(a.Score)                             AS MinAnswerScore,
        AVG(a.Score)::numeric(10,2)              AS AvgAnswerScore
    FROM Posts a
    WHERE a.PostTypeId = 2                         -- answers
    GROUP BY a.ParentId
),
u AS (
    SELECT
        u.Id,
        COALESCE(u.DisplayName,'Community') AS DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0) AS VoteBalance,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges
    FROM Users u
),
vote_summary AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN vt.Id = 5 THEN 1 ELSE 0 END) AS Favorites,
        COUNT(*) FILTER (WHERE vt.Id NOT IN (2,3,5)) AS OtherVotes
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
),
tag_stats AS (
    SELECT
        q.Id                                 AS QuestionId,
        t.Tag,
        COUNT(*) OVER (PARTITION BY t.Tag)   AS TagUsage
    FROM q
    CROSS JOIN LATERAL
        unnest(string_to_array(trim(both '<>' FROM q.Tags), '><')) AS t(Tag)
),
ranked_tags AS (
    SELECT
        ts.QuestionId,
        ts.Tag,
        ts.TagUsage,
        ROW_NUMBER() OVER (PARTITION BY ts.QuestionId ORDER BY ts.TagUsage DESC, ts.Tag) AS TagRank
    FROM tag_stats ts
)
SELECT
    q.Id                                 AS QuestionId,
    q.Title,
    q.CreationDate,
    COALESCE(u.DisplayName,'Community')  AS OwnerName,
    COALESCE(u.Reputation,0)              AS OwnerReputation,
    q.QuestionScore,
    q.Favorites,
    q.Views,
    COALESCE(ans.TotalAnswers,0)          AS AnswerCount,
    COALESCE(ans.MaxAnswerScore,0)        AS TopAnswerScore,
    COALESCE(ans.AvgAnswerScore,0)        AS AvgAnswerScore,
    COALESCE(vs.UpVotes,0)                AS QuestionUpVotes,
    COALESCE(vs.DownVotes,0)              AS QuestionDownVotes,
    COALESCE(u.GoldBadges,0)              AS OwnerGoldBadges,
    COALESCE(u.SilverBadges,0)            AS OwnerSilverBadges,
    COALESCE(u.BronzeBadges,0)            AS OwnerBronzeBadges,
    STRING_AGG(CASE WHEN rt.TagRank <= 3 THEN rt.Tag END, ', ') FILTER (WHERE rt.TagRank <= 3) AS Top3Tags,
    CASE
        WHEN q.ClosedDate IS NOT NULL               THEN 'Closed'
        WHEN q.CommunityOwnedDate IS NOT NULL       THEN 'CommunityOwned'
        ELSE 'Open'
    END                                      AS Status,
    CASE
        WHEN q.Tags IS NULL OR trim(q.Tags) = ''    THEN 'NoTags'
        ELSE NULL
    END                                      AS NullTagFlag
FROM q
LEFT JOIN ans      ON ans.QuestionId = q.Id
LEFT JOIN u        ON u.Id = q.OwnerUserId
LEFT JOIN vote_summary vs ON vs.PostId = q.Id
LEFT JOIN ranked_tags rt   ON rt.QuestionId = q.Id
GROUP BY
    q.Id, q.Title, q.CreationDate, u.DisplayName, u.Reputation,
    q.QuestionScore, q.Favorites, q.Views,
    ans.TotalAnswers, ans.MaxAnswerScore, ans.AvgAnswerScore,
    vs.UpVotes, vs.DownVotes,
    u.GoldBadges, u.SilverBadges, u.BronzeBadges,
    q.ClosedDate, q.CommunityOwnedDate, q.Tags
HAVING COUNT(*) FILTER (WHERE rt.TagRank <= 3) > 0
ORDER BY q.CreationDate DESC
LIMIT 100

UNION ALL

SELECT
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
WHERE FALSE;
