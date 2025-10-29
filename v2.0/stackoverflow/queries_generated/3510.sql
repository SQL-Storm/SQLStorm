-- {"query": "3510.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2804} 

WITH recent_posts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.Tags,
        regexp_split_to_table(p.Tags, '\\><') AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
),
tag_agg AS (
    SELECT
        rp.OwnerUserId,
        COUNT(DISTINCT rp.Tag)           AS DistinctTagCount,
        COUNT(rp.Tag)                    AS TagOccurrences
    FROM recent_posts rp
    GROUP BY rp.OwnerUserId
),
badge_counts AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(*)                           AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
answer_stats AS (
    SELECT
        q.OwnerUserId,
        COUNT(a.Id) FILTER (WHERE a.Score > 0)   AS PositiveAnswers,
        COUNT(a.Id) FILTER (WHERE a.Score <= 0)  AS NonPositiveAnswers,
        COUNT(a.Id)                               AS TotalAnswers,
        AVG(a.Score) FILTER (WHERE a.Score IS NOT NULL) AS AvgAnswerScore
    FROM Posts q
    LEFT JOIN Posts a
        ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.OwnerUserId
),
user_activity AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(bc.GoldBadges,0)     AS GoldBadges,
        COALESCE(bc.SilverBadges,0)   AS SilverBadges,
        COALESCE(bc.BronzeBadges,0)   AS BronzeBadges,
        COALESCE(bc.TotalBadges,0)    AS TotalBadges,
        COALESCE(ta.DistinctTagCount,0) AS DistinctTagCount,
        COALESCE(asr.PositiveAnswers,0) AS PositiveAnswers,
        COALESCE(asr.TotalAnswers,0)    AS TotalAnswers,
        COALESCE(asr.AvgAnswerScore,0)  AS AvgAnswerScore,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate) AS ReputationRank,
        RANK()      OVER (ORDER BY COALESCE(asr.AvgAnswerScore,0) DESC) AS AnswerScoreRank,
        CASE
            WHEN u.Location IS NULL OR u.Location = '' THEN 'unknown'
            ELSE u.Location
        END AS NormalizedLocation
    FROM Users u
    LEFT JOIN badge_counts bc   ON bc.UserId = u.Id
    LEFT JOIN tag_agg ta        ON ta.OwnerUserId = u.Id
    LEFT JOIN answer_stats asr  ON asr.OwnerUserId = u.Id
),
top_users AS (
    SELECT *
    FROM user_activity
    WHERE ReputationRank <= 100
      AND GoldBadges > 0
      AND (PositiveAnswers::float / NULLIF(TotalAnswers,0)) > 0.5
),
recent_voter_activity AS (
    SELECT
        v.UserId,
        COUNT(*) FILTER (WHERE vt.Name = 'UpMod')      AS UpVotes,
        COUNT(*) FILTER (WHERE vt.Name = 'DownMod')    AS DownVotes,
        COUNT(*) FILTER (WHERE vt.Name = 'Favorite')   AS Favorites,
        MAX(v.CreationDate)                           AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '90 days'
    GROUP BY v.UserId
),
combined AS (
    SELECT
        tu.Id,
        tu.DisplayName,
        tu.Reputation,
        tu.GoldBadges,
        tu.SilverBadges,
        tu.BronzeBadges,
        tu.TotalBadges,
        tu.DistinctTagCount,
        tu.PositiveAnswers,
        tu.TotalAnswers,
        tu.AvgAnswerScore,
        tu.ReputationRank,
        tu.AnswerScoreRank,
        tu.NormalizedLocation,
        COALESCE(rva.UpVotes,0)   AS UpVotesLast90d,
        COALESCE(rva.DownVotes,0) AS DownVotesLast90d,
        COALESCE(rva.Favorites,0) AS FavoritesLast90d,
        rva.LastVoteDate
    FROM top_users tu
    LEFT JOIN recent_voter_activity rva ON rva.UserId = tu.Id
)
SELECT *
FROM combined
WHERE (UpVotesLast90d + DownVotesLast90d) > 0

UNION ALL

SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    COALESCE(bc.GoldBadges,0),
    COALESCE(bc.SilverBadges,0),
    COALESCE(bc.BronzeBadges,0),
    COALESCE(bc.TotalBadges,0),
    0 AS DistinctTagCount,
    0 AS PositiveAnswers,
    0 AS TotalAnswers,
    0 AS AvgAnswerScore,
    NULL AS ReputationRank,
    NULL AS AnswerScoreRank,
    'inactive' AS NormalizedLocation,
    0 AS UpVotesLast90d,
    0 AS DownVotesLast90d,
    0 AS FavoritesLast90d,
    NULL AS LastVoteDate
FROM Users u
LEFT JOIN badge_counts bc ON bc.UserId = u.Id
WHERE u.Reputation < 100
  AND NOT EXISTS (
      SELECT 1 FROM Posts p
      WHERE p.OwnerUserId = u.Id
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '180 days'
  )
ORDER BY Reputation DESC NULLS LAST, UpVotesLast90d DESC;
