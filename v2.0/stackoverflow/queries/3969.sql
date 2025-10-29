-- {"query": "3969.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2000}
WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2)                AS AnswerCount,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 10)     AS CloseVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)                  AS UpVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)                  AS DownVotesGiven
    FROM Users u
    LEFT JOIN Posts p          ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v          ON v.UserId = u.Id
    LEFT JOIN PostHistory ph   ON ph.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

TopTagAnswers AS (
    SELECT
        t.TagName,
        a.OwnerUserId,
        COUNT(*)                                            AS AnswersInTag,
        AVG(a.Score)                                        AS AvgScore,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY AVG(a.Score) DESC) AS rn
    FROM Posts a
    JOIN Posts q
        ON q.Id = a.ParentId AND q.PostTypeId = 1
    LEFT JOIN (
        SELECT p.Id,
               UNNEST(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS tag
        FROM Posts p
    ) AS taglist ON taglist.Id = q.Id
    JOIN Tags t
        ON t.TagName = taglist.tag
    WHERE a.PostTypeId = 2
    GROUP BY t.TagName, a.OwnerUserId
),

UserBadgeStats AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        SUM(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END)       AS TagBasedBadges
    FROM Badges b
    GROUP BY b.UserId
),

QualifiedUsers AS (
    SELECT
        us.Id,
        COALESCE(us.DisplayName, 'Anonymous')                     AS DisplayName,
        us.Reputation,
        us.AnswerCount,
        (us.UpVotesGiven - us.DownVotesGiven)                     AS NetVotesGiven,
        COALESCE(ubs.GoldBadges,   0)                             AS GoldBadges,
        COALESCE(ubs.SilverBadges, 0)                             AS SilverBadges,
        COALESCE(ubs.BronzeBadges, 0)                             AS BronzeBadges,
        COALESCE(ubs.TagBasedBadges,0)                            AS TagBasedBadges,
        tt.TagName,
        tt.AnswersInTag,
        tt.AvgScore
    FROM UserStats us
    LEFT JOIN UserBadgeStats ubs
           ON ubs.UserId = us.Id
    LEFT JOIN (
        SELECT TagName, OwnerUserId, AnswersInTag, AvgScore
        FROM TopTagAnswers
        WHERE rn = 1
    ) tt
           ON tt.OwnerUserId = us.Id
    WHERE us.Reputation > 10000
      AND (us.AnswerCount IS NULL OR us.AnswerCount > 5)
      AND EXISTS (
            SELECT 1
            FROM Posts p
            WHERE p.OwnerUserId = us.Id
              AND p.PostTypeId = 1
              AND p.ClosedDate IS NULL
              AND p.Score >= 10
              AND p.Tags IS NOT NULL
              AND POSITION('<sql>' IN LOWER(p.Tags)) > 0
          )
)

SELECT *
FROM (
    SELECT
        Id,
        DisplayName,
        Reputation,
        AnswerCount,
        NetVotesGiven,
        GoldBadges,
        SilverBadges,
        BronzeBadges,
        TagBasedBadges,
        TagName,
        AnswersInTag,
        AvgScore,
        1 AS sort_order,
        Reputation AS sort_rep,
        GoldBadges AS sort_gold
    FROM QualifiedUsers

    UNION ALL

    SELECT
        NULL AS Id,
        'Aggregate' AS DisplayName,
        SUM(Representation.Reputation) AS Reputation,
        SUM(Representation.AnswerCount) AS AnswerCount,
        SUM(Representation.NetVotesGiven) AS NetVotesGiven,
        SUM(Representation.GoldBadges) AS GoldBadges,
        SUM(Representation.SilverBadges) AS SilverBadges,
        SUM(Representation.BronzeBadges) AS BronzeBadges,
        SUM(Representation.TagBasedBadges) AS TagBasedBadges,
        NULL AS TagName,
        NULL AS AnswersInTag,
        NULL AS AvgScore,
        2 AS sort_order,
        SUM(Representation.Reputation) AS sort_rep,
        SUM(Representation.GoldBadges) AS sort_gold
    FROM QualifiedUsers AS Representation
) AS combined
ORDER BY sort_order, sort_rep DESC, sort_gold DESC
LIMIT 100;