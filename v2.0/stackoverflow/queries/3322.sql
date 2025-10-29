-- {"query": "3322.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1317}
WITH
    top_questions AS (
        SELECT
            p.Id                     AS QuestionId,
            p.Title,
            p.CreationDate,
            p.Score                  AS QuestionScore,
            p.ViewCount,
            p.Tags,
            u.Id                     AS OwnerUserId,
            u.DisplayName            AS OwnerDisplayName,
            COALESCE(u.Reputation, 0) AS OwnerReputation,
            array_length(string_to_array(substring(p.Tags FROM 2 FOR (length(p.Tags) - 2)), '><'), 1) AS TagCount,
            (
                SELECT a.Id
                FROM Posts a
                WHERE a.PostTypeId = 2
                  AND a.ParentId = p.Id
                ORDER BY a.CreationDate DESC
                LIMIT 1
            ) AS LatestAnswerId
        FROM Posts p
        LEFT JOIN Users u
               ON u.Id = p.OwnerUserId
        WHERE p.PostTypeId = 1
          AND p.Score >= 10
          AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30 days'
    ),

    user_badges AS (
        SELECT
            b.UserId,
            COUNT(*)                              AS TotalBadges,
            COUNT(*) FILTER (WHERE b.Class = 1)   AS GoldBadges,
            COUNT(*) FILTER (WHERE b.Class = 2)   AS SilverBadges,
            COUNT(*) FILTER (WHERE b.Class = 3)   AS BronzeBadges,
            MAX(b.Date)                           AS MostRecentBadgeDate
        FROM Badges b
        GROUP BY b.UserId
    ),

    latest_votes AS (
        SELECT
            v.PostId,
            v.VoteTypeId,
            v.UserId,
            v.CreationDate,
            ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) AS rn
        FROM Votes v
    ),

    answer_ranking AS (
        SELECT
            a.Id,
            a.ParentId               AS QuestionId,
            a.Score,
            a.CreationDate,
            RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS ScoreRank
        FROM Posts a
        WHERE a.PostTypeId = 2
    ),

    combined AS (
        SELECT
            q.QuestionId,
            q.Title,
            q.CreationDate,
            q.QuestionScore,
            q.ViewCount,
            q.TagCount,
            q.OwnerUserId,
            q.OwnerDisplayName,
            q.OwnerReputation,
            COALESCE(b.TotalBadges, 0)   AS OwnerTotalBadges,
            COALESCE(b.GoldBadges, 0)    AS OwnerGoldBadges,
            COALESCE(b.SilverBadges, 0)  AS OwnerSilverBadges,
            COALESCE(b.BronzeBadges, 0)  AS OwnerBronzeBadges,
            b.MostRecentBadgeDate,
            lv.VoteTypeId                AS LastVoteType,
            lv.UserId                    AS LastVoterUserId,
            lv.CreationDate              AS LastVoteDate,
            ar.Id                        AS TopAnswerId,
            ar.Score                     AS TopAnswerScore,
            ar.ScoreRank
        FROM top_questions q
        LEFT JOIN user_badges b
               ON b.UserId = q.OwnerUserId
        LEFT JOIN latest_votes lv
               ON lv.PostId = q.QuestionId AND lv.rn = 1
        LEFT JOIN answer_ranking ar
               ON ar.QuestionId = q.QuestionId
              AND ar.ScoreRank = 1
    )

SELECT *
FROM combined

UNION ALL

SELECT
    p.Id                               AS QuestionId,
    p.Title,
    p.CreationDate,
    p.Score                            AS QuestionScore,
    p.ViewCount,
    array_length(string_to_array(substring(p.Tags FROM 2 FOR (length(p.Tags) - 2)), '><'), 1) AS TagCount,
    NULL                               AS OwnerUserId,
    NULL                               AS OwnerDisplayName,
    0                                  AS OwnerReputation,
    0                                  AS OwnerTotalBadges,
    0                                  AS OwnerGoldBadges,
    0                                  AS OwnerSilverBadges,
    0                                  AS OwnerBronzeBadges,
    NULL                               AS MostRecentBadgeDate,
    NULL                               AS LastVoteType,
    NULL                               AS LastVoterUserId,
    NULL                               AS LastVoteDate,
    NULL                               AS TopAnswerId,
    NULL                               AS TopAnswerScore,
    NULL                               AS ScoreRank
FROM Posts p
WHERE p.PostTypeId = 1
  AND p.OwnerUserId IS NULL
  AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30 days'
ORDER BY QuestionScore DESC NULLS LAST, QuestionId;