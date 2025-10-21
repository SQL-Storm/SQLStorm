WITH
TopUsers AS (
    SELECT
        U.Id as UserId,
        U.DisplayName,
        U.Reputation,
        DENSE_RANK() OVER (ORDER BY U.Reputation DESC) as RepRank,
        COUNT(DISTINCT B.Id) as BadgeCount,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) as GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) as SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) as BronzeBadges
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    WHERE U.Reputation > (
        SELECT AVG(Reputation) FROM Users WHERE Reputation > 0
    )
    GROUP BY U.Id, U.DisplayName, U.Reputation
),
UserPostsAndAnswers AS (
    SELECT
        P.OwnerUserId as UserId,
        COUNT(*) FILTER (WHERE P.PostTypeId = 1) as QuestionCount,
        COUNT(*) FILTER (WHERE P.PostTypeId = 2) as AnswerCount,
        SUM(CASE WHEN P.Score > 0 THEN P.Score ELSE 0 END) as TotalPositiveScore,
        MAX(P.ViewCount) as MaxViews
    FROM Posts P
    WHERE P.OwnerUserId IS NOT NULL AND P.OwnerUserId != -1
    GROUP BY P.OwnerUserId
),
LatestComments AS (
    SELECT
        C1.Id,
        C1.PostId,
        C1.Text,
        C1.UserId,
        C1.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY C1.PostId ORDER BY C1.CreationDate DESC) as rownum
    FROM Comments C1
)
SELECT
    TU.UserId,
    TU.DisplayName,
    TU.Reputation,
    TU.BadgeCount,
    TU.GoldBadges,
    TU.SilverBadges,
    TU.BronzeBadges,
    UP.AnswerCount,
    UP.QuestionCount,
    UP.TotalPositiveScore,
    UP.MaxViews,
    COALESCE(BestPost.Title, '(No Top Answer)') as TopAnswerTitle,
    LEAST(UP.QuestionCount, UP.AnswerCount) as MinQuestionsAnswers,
    CASE
        WHEN TU.GoldBadges = 0 THEN 0
        ELSE (TU.GoldBadges / NULLIF(GREATEST(TU.SilverBadges, 1), 0))::double precision
    END as GoldToSilverBadgeRatio,
    CASE
        WHEN TU.Reputation > 50000 THEN 'Legend'
        WHEN TU.Reputation > 10000 THEN 'Pro'
        ELSE 'Rising'
    END as UserTier,
    STRING_AGG(DISTINCT T.TagName, ', ' ORDER BY T.TagName) as TopTags,
    LC.Text as LatestComment
FROM TopUsers TU
LEFT JOIN UserPostsAndAnswers UP ON TU.UserId = UP.UserId
LEFT JOIN LATERAL (
    SELECT P.Title
    FROM Posts P
    WHERE P.PostTypeId = 2 AND P.OwnerUserId = TU.UserId
    ORDER BY P.Score DESC NULLS LAST
    LIMIT 1
) BestPost ON TRUE
LEFT JOIN Posts QP ON QP.OwnerUserId = TU.UserId AND QP.PostTypeId = 1
LEFT JOIN LATERAL (
    SELECT DISTINCT
        unnest(string_to_array(substring(QP.Tags, 2, length(QP.Tags)-2), '><')) AS TagName
    WHERE QP.Tags IS NOT NULL
    LIMIT 5
) TagList ON TRUE
LEFT JOIN Tags T ON T.TagName = TagList.TagName
LEFT JOIN LatestComments LC ON LC.UserId = TU.UserId AND LC.rownum = 1
WHERE 
    TU.RepRank <= 100
    AND (UP.AnswerCount > 10 OR UP.QuestionCount > 5)
    AND (TU.SilverBadges IS NOT NULL AND TU.SilverBadges > 0)
    AND (UP.MaxViews IS NULL OR UP.MaxViews < 1000000)
GROUP BY
    TU.UserId, TU.DisplayName, TU.Reputation, TU.BadgeCount, TU.GoldBadges, TU.SilverBadges,
    TU.BronzeBadges, UP.AnswerCount, UP.QuestionCount, UP.TotalPositiveScore, UP.MaxViews,
    BestPost.Title, LC.Text
ORDER BY
    TU.Reputation DESC, UP.TotalPositiveScore DESC
LIMIT 50;