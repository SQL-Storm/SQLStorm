WITH
    UserStats AS (
        SELECT
            u.Id AS UserId,
            u.DisplayName,
            u.Reputation,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
            MAX(p.CreationDate) AS LastPostDate
        FROM Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        LEFT JOIN Votes v ON v.PostId = p.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),
    TopTagAnswers AS (
        SELECT
            a.OwnerUserId AS UserId,
            UNNEST(STRING_TO_ARRAY(SUBSTRING(a.Tags FROM 2 FOR CHAR_LENGTH(a.Tags)-2), '><')) AS Tag,
            a.Id AS AnswerId,
            a.Score,
            ROW_NUMBER() OVER (PARTITION BY a.OwnerUserId
                               ORDER BY a.Score DESC, a.CreationDate DESC) AS rn
        FROM Posts a
        WHERE a.PostTypeId = 2
          AND a.Tags IS NOT NULL
    ),
    UserBadgeAgg AS (
        SELECT
            b.UserId,
            COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
            COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
            COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
            STRING_AGG(DISTINCT b.Name, ', ') AS BadgeList
        FROM Badges b
        GROUP BY b.UserId
    ),
    RecentClosedQuestions AS (
        SELECT
            ph.PostId,
            MAX(ph.CreationDate) AS ClosedDate,
            MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS CloseReasonJson
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 10
        GROUP BY ph.PostId
    ),
    Combined AS (
        SELECT
            us.UserId,
            us.DisplayName,
            us.Reputation,
            us.QuestionCount,
            us.AnswerCount,
            us.UpVoteCount,
            us.DownVoteCount,
            ub.GoldBadges,
            ub.SilverBadges,
            ub.BronzeBadges,
            ub.BadgeList,
            ta.Tag,
            ta.Score AS TopAnswerScore,
            rcq.ClosedDate,
            rcq.CloseReasonJson
        FROM UserStats us
        LEFT JOIN UserBadgeAgg ub
            ON ub.UserId = us.UserId
        LEFT JOIN TopTagAnswers ta
            ON ta.UserId = us.UserId AND ta.rn = 1
        LEFT JOIN RecentClosedQuestions rcq
            ON rcq.PostId = (
                SELECT p.Id
                FROM Posts p
                WHERE p.OwnerUserId = us.UserId
                  AND p.PostTypeId = 1
                  AND EXISTS (
                      SELECT 1
                      FROM PostHistory ph2
                      WHERE ph2.PostId = p.Id
                        AND ph2.PostHistoryTypeId = 10
                  )
                ORDER BY p.CreationDate DESC
                LIMIT 1
            )
    ),
    MainSelection AS (
        SELECT
            UserId,
            DisplayName,
            Reputation,
            QuestionCount,
            AnswerCount,
            UpVoteCount,
            DownVoteCount,
            GoldBadges,
            SilverBadges,
            BronzeBadges,
            BadgeList,
            Tag,
            TopAnswerScore,
            ClosedDate,
            CloseReasonJson
        FROM Combined
        WHERE (Reputation > 10000 OR GoldBadges IS NOT NULL)
          AND (TopAnswerScore IS NULL OR TopAnswerScore >= 10)
    ),
    SummarySelection AS (
        SELECT
            CAST(NULL AS BIGINT) AS UserId,
            'Summary' AS DisplayName,
            CAST(NULL AS BIGINT) AS Reputation,
            SUM(QuestionCount) AS QuestionCount,
            SUM(AnswerCount) AS AnswerCount,
            SUM(UpVoteCount) AS UpVoteCount,
            SUM(DownVoteCount) AS DownVoteCount,
            CAST(NULL AS INTEGER) AS GoldBadges,
            CAST(NULL AS INTEGER) AS SilverBadges,
            CAST(NULL AS INTEGER) AS BronzeBadges,
            CAST(NULL AS VARCHAR) AS BadgeList,
            CAST(NULL AS VARCHAR) AS Tag,
            CAST(NULL AS INTEGER) AS TopAnswerScore,
            CAST(NULL AS TIMESTAMP) AS ClosedDate,
            CAST(NULL AS VARCHAR) AS CloseReasonJson
        FROM Combined
        WHERE Reputation IS NOT NULL
    ),
    FinalMain AS (
        SELECT *
        FROM MainSelection
        ORDER BY Reputation DESC NULLS LAST, GoldBadges DESC NULLS LAST
        LIMIT 100
    )
SELECT *
FROM (
    SELECT * FROM FinalMain
    UNION ALL
    SELECT * FROM SummarySelection
) t;