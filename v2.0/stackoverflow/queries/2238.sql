-- {"query": "2238.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1501}
WITH RecursiveUserBadgeRanks AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        b.Class,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY b.Date DESC) AS RecentBadgeRank,
        COUNT(b.Id) OVER (PARTITION BY u.Id, b.Class) AS BadgeClassCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE b.Class IS NOT NULL
),
TopUsersWithGoldBadges AS (
    SELECT DISTINCT
        r.UserId,
        r.DisplayName,
        r.BadgeClassCount
    FROM RecursiveUserBadgeRanks r
    WHERE r.Class = 1 AND r.RecentBadgeRank <= 5
),
LatestPostEdits AS (
    SELECT
        ph.PostId,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6) -- Edit Title, Edit Body, Edit Tags
    GROUP BY ph.PostId
),
FilteredPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.AcceptedAnswerId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.Title,
        p.AnswerCount,
        p.FavoriteCount,
        COALESCE(lp.LastEditDate, p.LastActivityDate) AS EffectiveLastEditDate,
        p.ClosedDate
    FROM Posts p
    LEFT JOIN LatestPostEdits lp ON p.Id = lp.PostId
    WHERE p.PostTypeId = 1 -- Questions only
      AND p.Score > 5
      AND p.ViewCount > 1000
      AND (p.ClosedDate IS NULL OR p.ClosedDate > (CAST('2024-10-01' AS date) - INTERVAL '30 days'))
),
UserPostTags AS (
    -- move set-returning function into a lateral to avoid aggregating SRFs directly
    SELECT
        fp.OwnerUserId,
        t.tag
    FROM FilteredPosts fp
    CROSS JOIN LATERAL (
        SELECT UNNEST(string_to_array(TRIM(BOTH '<>' FROM fp.Tags), '><')) AS tag
    ) t
    WHERE fp.OwnerUserId IS NOT NULL
),
UserPostAggregates AS (
    SELECT
        up.OwnerUserId,
        COUNT(fp.Id) AS QuestionCount,
        AVG(fp.Score) AS AvgQuestionScore,
        SUM(fp.ViewCount) AS TotalViews,
        STRING_AGG(DISTINCT up.tag, ',') AS UniqueTags
    FROM FilteredPosts fp
    JOIN UserPostTags up ON fp.OwnerUserId = up.OwnerUserId
    WHERE fp.OwnerUserId IS NOT NULL
    GROUP BY up.OwnerUserId
),
TopQuestionsWithAnswers AS (
    SELECT
        fp.Id AS QuestionId,
        fp.Title,
        fp.CreationDate AS QuestionCreationDate,
        fp.Score AS QuestionScore,
        fp.ViewCount AS QuestionViewCount,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerOwnerUserId,
        a.CreationDate AS AnswerCreationDate,
        a.Score AS AnswerScore,
        a.ParentId,
        ROW_NUMBER() OVER (PARTITION BY fp.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM FilteredPosts fp
    LEFT JOIN Posts a ON a.ParentId = fp.Id AND a.PostTypeId = 2
),
AcceptedAnswerDetails AS (
    SELECT
        tq.QuestionId,
        tq.Title,
        tq.QuestionCreationDate,
        tq.QuestionScore,
        tq.QuestionViewCount,
        tq.AnswerId,
        tq.AnswerOwnerUserId,
        tq.AnswerCreationDate,
        tq.AnswerScore,
        u.DisplayName AS AnswerOwnerDisplayName,
        CASE
            WHEN tq.AnswerId = fp.AcceptedAnswerId THEN 1
            ELSE 0
        END AS IsAcceptedAnswer,
        ROW_NUMBER() OVER (PARTITION BY tq.QuestionId ORDER BY tq.AnswerScore DESC) AS AnswerScoreRank
    FROM TopQuestionsWithAnswers tq
    JOIN FilteredPosts fp ON fp.Id = tq.QuestionId
    LEFT JOIN Users u ON tq.AnswerOwnerUserId = u.Id
),
FilteredAcceptedAnswers AS (
    SELECT *
    FROM AcceptedAnswerDetails
    WHERE IsAcceptedAnswer = 1
       OR AnswerScoreRank = 1 -- Top scoring answer if no accepted answer
),
ComplexUserStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(upa.QuestionCount, 0) AS QuestionCount,
        COALESCE(upa.AvgQuestionScore, 0.0) AS AvgQuestionScore,
        COALESCE(upa.TotalViews, 0) AS TotalPostViews,
        COALESCE(bd.BadgeCount, 0) AS TotalBadges,
        COALESCE(bd.GoldBadges, 0) AS GoldBadges,
        COALESCE(bd.SilverBadges, 0) AS SilverBadges,
        COALESCE(bd.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(up.LatestPostDate, u.CreationDate) AS LastActive,
        upa.UniqueTags
    FROM Users u
    LEFT JOIN UserPostAggregates upa ON u.Id = upa.OwnerUserId
    LEFT JOIN (
        SELECT
            UserId,
            COUNT(*) AS BadgeCount,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
        FROM Badges
        GROUP BY UserId
    ) bd ON u.Id = bd.UserId
    LEFT JOIN (
        SELECT
            OwnerUserId AS UserId,
            MAX(COALESCE(LastActivityDate, CreationDate)) AS LatestPostDate
        FROM Posts
        GROUP BY OwnerUserId
    ) up ON u.Id = up.UserId
    WHERE u.Reputation > 1000
),
FinalResult AS (
    SELECT
        cus.UserId,
        cus.DisplayName,
        cus.Reputation,
        cus.QuestionCount,
        ROUND(cus.AvgQuestionScore,2) AS AvgQuestionScore,
        cus.TotalPostViews,
        cus.TotalBadges,
        cus.GoldBadges,
        cus.SilverBadges,
        cus.BronzeBadges,
        cus.LastActive,
        cus.UniqueTags,
        fqa.QuestionId,
        fqa.Title AS QuestionTitle,
        fqa.QuestionCreationDate,
        fqa.QuestionScore,
        fqa.QuestionViewCount,
        fqa.AnswerId,
        fqa.AnswerOwnerUserId,
        fqa.AnswerOwnerDisplayName,
        fqa.AnswerCreationDate,
        fqa.AnswerScore,
        aurt.Reputation AS AnswerUserReputation,
        ROW_NUMBER() OVER (PARTITION BY cus.UserId ORDER BY cus.Reputation DESC, cus.TotalBadges DESC) AS UserRank
    FROM ComplexUserStats cus
    LEFT JOIN FilteredAcceptedAnswers fqa ON fqa.AnswerOwnerUserId = cus.UserId
    LEFT JOIN Users aurt ON fqa.AnswerOwnerUserId = aurt.Id
    WHERE cus.QuestionCount > 5
)
SELECT *
FROM FinalResult
WHERE UserRank <= 20
ORDER BY UserRank, QuestionScore DESC, AnswerScore DESC;