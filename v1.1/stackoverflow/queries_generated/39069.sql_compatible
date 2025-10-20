WITH QuestionTags AS (
    SELECT 
        p.Id                    AS QuestionId,
        unnest(
            string_to_array(
                substring(p.Tags,2,length(p.Tags)-2),
                '><'
            )
        )                       AS TagName,
        p.CreationDate          AS QuestionDate,
        p.AcceptedAnswerId,
        p.Score                  AS QuestionScore,
        p.ViewCount,
        p.CommentCount
    FROM Posts p
    WHERE p.PostTypeId = 1
),
Answers AS (
    SELECT
        a.Id                     AS AnswerId,
        a.ParentId               AS QuestionId,
        a.OwnerUserId,
        a.CreationDate           AS AnswerDate,
        a.Score                  AS AnswerScore,
        a.CommentCount           AS AnswerCommentCount
    FROM Posts a
    WHERE a.PostTypeId = 2
),
AnswerStats AS (
    SELECT
        qt.TagName,
        qt.QuestionId,
        ans.AnswerId,
        EXTRACT(EPOCH FROM (ans.AnswerDate - qt.QuestionDate)) / 3600 AS HoursToAnswer,
        ans.OwnerUserId,
        ans.AnswerScore
    FROM QuestionTags qt
    JOIN Answers ans
      ON ans.QuestionId = qt.QuestionId
    WHERE qt.QuestionDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
),
AcceptedStats AS (
    SELECT
        A.TagName,
        A.QuestionId,
        A.HoursToAnswer,
        A.OwnerUserId,
        A.AnswerScore
    FROM AnswerStats A
    JOIN QuestionTags qt
      ON qt.QuestionId = A.QuestionId
     AND qt.TagName     = A.TagName
     AND qt.AcceptedAnswerId = A.AnswerId
),
VotesByQuestion AS (
    SELECT
        v.PostId AS QuestionId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS Favorites
    FROM Votes v
    GROUP BY v.PostId
),
UserBadgeStats AS (
    SELECT
        u.Id AS UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b
      ON b.UserId = u.Id
    GROUP BY u.Id
),
TagAggregates AS (
    SELECT
        qt.TagName,
        COUNT(DISTINCT qt.QuestionId)            AS TotalQuestions,
        COUNT(DISTINCT as2.OwnerUserId)          AS ActiveAnswerers,
        ROUND(AVG(as2.HoursToAnswer),2)          AS AvgAnswerTimeHrs,
        ROUND(AVG(as2.AnswerScore),2)            AS AvgAnswerScore,
        SUM(vb.UpVotes)                          AS TotalUpVotes,
        SUM(vb.DownVotes)                        AS TotalDownVotes,
        SUM(vb.Favorites)                        AS TotalFavorites
    FROM QuestionTags qt
    JOIN AcceptedStats as2
      ON as2.QuestionId = qt.QuestionId
     AND as2.TagName     = qt.TagName
    LEFT JOIN VotesByQuestion vb
      ON vb.QuestionId = qt.QuestionId
    GROUP BY qt.TagName
),
TopUsersPerTag AS (
    SELECT
        A.TagName,
        A.OwnerUserId AS UserId,
        ROW_NUMBER() OVER (
            PARTITION BY A.TagName
            ORDER BY COUNT(*) DESC, AVG(A.AnswerScore) DESC
        ) AS RankByAnswersCount
    FROM AnswerStats A
    GROUP BY A.TagName, A.OwnerUserId
)
SELECT
    ta.TagName,
    ta.TotalQuestions,
    ta.ActiveAnswerers,
    ta.AvgAnswerTimeHrs,
    ta.AvgAnswerScore,
    ta.TotalUpVotes,
    ta.TotalDownVotes,
    ta.TotalFavorites,
    tu.UserId            AS TopResponder,
    u.DisplayName        AS TopResponderName,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges
FROM TagAggregates ta
JOIN TopUsersPerTag tu
  ON tu.TagName = ta.TagName
 AND tu.RankByAnswersCount = 1
JOIN Users u
  ON u.Id = tu.UserId
LEFT JOIN UserBadgeStats ub
  ON ub.UserId = u.Id
ORDER BY ta.TotalQuestions DESC, ta.AvgAnswerTimeHrs ASC
LIMIT 10;