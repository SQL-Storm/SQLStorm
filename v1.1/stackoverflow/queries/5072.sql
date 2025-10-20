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
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) as QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) as AnswerCount,
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
    LEAST(COALESCE(UP.QuestionCount,0), COALESCE(UP.AnswerCount,0)) as MinQuestionsAnswers,
    CASE
        WHEN NULLIF(TU.GoldBadges,0) IS NULL THEN NULL
        ELSE NULLIF(TU.GoldBadges,0) / NULLIF(GREATEST(TU.SilverBadges,1),0)
    END as GoldToSilverBadgeRatio,
    CASE
        WHEN TU.Reputation > 50000 THEN 'Legend'
        WHEN TU.Reputation > 10000 THEN 'Pro'
        ELSE 'Rising'
    END as UserTier,
    STRING_AGG(T.TagName, ', ' ORDER BY T.TagName) as TopTags,
    LC.Text as LatestComment
FROM TopUsers TU
LEFT JOIN UserPostsAndAnswers UP ON TU.UserId = UP.UserId
LEFT JOIN (
    SELECT P.OwnerUserId, P.Title, ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC) as rn
    FROM Posts P
    WHERE P.PostTypeId = 2
) BestPost ON BestPost.OwnerUserId = TU.UserId AND BestPost.rn = 1
LEFT JOIN Posts QP ON QP.OwnerUserId = TU.UserId AND QP.PostTypeId = 1
LEFT JOIN (
    SELECT QP.OwnerUserId as OwnerUserId, unnest_tags.tag AS TagName
    FROM Posts QP,
         UNNEST(string_to_array(SUBSTRING(QP.Tags FROM 2 FOR (LENGTH(QP.Tags)-2)), '><')) AS unnest_tags(tag)
    WHERE QP.Tags IS NOT NULL
) TagList ON TagList.OwnerUserId = QP.OwnerUserId
LEFT JOIN Tags T ON T.TagName = TagList.TagName
LEFT JOIN LatestComments LC ON LC.UserId = TU.UserId AND LC.rownum = 1
WHERE 
    TU.RepRank <= 100
    AND (COALESCE(UP.AnswerCount,0) > 10 OR COALESCE(UP.QuestionCount,0) > 5)
    AND (TU.SilverBadges IS NOT NULL AND TU.SilverBadges > 0)
    AND (UP.MaxViews IS NULL OR UP.MaxViews < 1000000)
GROUP BY
    TU.UserId, TU.DisplayName, TU.Reputation, TU.BadgeCount, TU.GoldBadges, TU.SilverBadges,
    TU.BronzeBadges, UP.AnswerCount, UP.QuestionCount, UP.TotalPositiveScore, UP.MaxViews,
    BestPost.Title, LC.Text
ORDER BY
    TU.Reputation DESC, UP.TotalPositiveScore DESC
LIMIT 50;