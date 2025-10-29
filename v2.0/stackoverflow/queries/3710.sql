-- {"query": "3710.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2524}
WITH
UserPosts AS (
    SELECT
        p.OwnerUserId                AS UserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1)                AS QuestionCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2)                AS AnswerCount,
        AVG(p.Score)   FILTER (WHERE p.PostTypeId = 1)          AS AvgQuestionScore,
        AVG(p.Score)   FILTER (WHERE p.PostTypeId = 2)          AS AvgAnswerScore,
        MAX(p.CreationDate)                                   AS LastPostDate,
        MAX(CASE WHEN p.PostTypeId = 2 THEN p.Score END)      AS TopAnswerScore
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserBadges AS (
    SELECT
        b.UserId                                     AS UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserActivity AS (
    SELECT
        u.Id                                            AS UserId,
        COALESCE(u.DisplayName,'[deleted]')             AS DisplayName,
        u.Reputation,
        COALESCE(up.QuestionCount,0)                     AS QuestionCount,
        COALESCE(up.AnswerCount,0)                       AS AnswerCount,
        COALESCE(up.AvgQuestionScore,0)                 AS AvgQuestionScore,
        COALESCE(up.AvgAnswerScore,0)                   AS AvgAnswerScore,
        COALESCE(up.TopAnswerScore,0)                   AS TopAnswerScore,
        COALESCE(up.LastPostDate, CAST('1900-01-01' AS TIMESTAMP)) AS LastPostDate,
        COALESCE(ub.GoldBadges,0)                       AS GoldBadges,
        COALESCE(ub.SilverBadges,0)                     AS SilverBadges,
        COALESCE(ub.BronzeBadges,0)                     AS BronzeBadges,
        COALESCE(EXTRACT(day FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - 
                 COALESCE(up.LastPostDate, CAST('2024-10-01 12:34:56' AS TIMESTAMP)))),0) AS DaysSinceLastPost,
        ( COALESCE(up.QuestionCount,0) * 2
        + COALESCE(up.AnswerCount,0)   * 3
        + COALESCE(up.AvgQuestionScore,0) * 1.5
        + COALESCE(up.AvgAnswerScore,0)   * 2
        + COALESCE(ub.GoldBadges,0)    * 5
        + COALESCE(ub.SilverBadges,0)  * 3
        + COALESCE(ub.BronzeBadges,0)  * 1
        - COALESCE(EXTRACT(day FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) -
                 COALESCE(up.LastPostDate, CAST('2024-10-01 12:34:56' AS TIMESTAMP)))),0) * 0.1
        )                                                AS CompositeScore,
        (SELECT c.Text
         FROM Comments c
         WHERE c.UserId = u.Id
         ORDER BY c.CreationDate DESC
         LIMIT 1)                                      AS LatestComment
    FROM Users u
    LEFT JOIN UserPosts up   ON u.Id = up.UserId
    LEFT JOIN UserBadges ub  ON u.Id = ub.UserId
),
RankedUsers AS (
    SELECT
        ua.*,
        ROW_NUMBER() OVER (ORDER BY ua.CompositeScore DESC) AS RankByScore
    FROM UserActivity ua
),
TopActive AS (
    SELECT *
    FROM RankedUsers
    WHERE CompositeScore > 0
    ORDER BY CompositeScore DESC
    LIMIT 5
),
ZeroActivity AS (
    SELECT *
    FROM RankedUsers
    WHERE QuestionCount = 0
      AND AnswerCount   = 0
      AND GoldBadges   = 0
      AND SilverBadges = 0
      AND BronzeBadges = 0
    ORDER BY Reputation DESC
    LIMIT 5
)

SELECT
    UserId,
    DisplayName,
    Reputation,
    QuestionCount,
    AnswerCount,
    AvgQuestionScore,
    AvgAnswerScore,
    TopAnswerScore,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    LastPostDate,
    DaysSinceLastPost,
    CompositeScore,
    RankByScore,
    TRIM(BOTH ' ' FROM (COALESCE(DisplayName,'') || ' - Score: ' ||
         COALESCE(CAST(CompositeScore AS VARCHAR), '0'))) AS NameScoreLabel,
    LatestComment
FROM (
    SELECT * FROM TopActive
    UNION ALL
    SELECT * FROM ZeroActivity
) AS final_set
ORDER BY CompositeScore DESC, RankByScore;