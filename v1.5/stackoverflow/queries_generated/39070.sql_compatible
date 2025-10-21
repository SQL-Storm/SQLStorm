WITH TagPosts AS (
    SELECT
        p.Id         AS QuestionId,
        p.OwnerUserId,
        unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
        CAST(p.CreationDate AS DATE) AS CreatedDate
    FROM Posts p
    WHERE p.PostTypeId = 1
),
TopTags AS (
    SELECT
        TagName,
        COUNT(*) AS QuestionCount
    FROM TagPosts
    GROUP BY TagName
    ORDER BY QuestionCount DESC
    LIMIT 5
),
TagStats AS (
    SELECT
        tt.TagName,
        tt.QuestionCount,
        COUNT(a.Id)                         AS AnswerCount,
        AVG(a.Score)                        AS AvgAnswerScore,
        AVG(q.Score) FILTER (WHERE q.Score >= 0) AS AvgQuestionScore,
        MAX(q.ViewCount)                    AS MaxQuestionViews
    FROM TopTags tt
    JOIN TagPosts tp
      ON tp.TagName = tt.TagName
    JOIN Posts q
      ON q.Id = tp.QuestionId
    LEFT JOIN Posts a
      ON a.ParentId = q.Id
     AND a.PostTypeId = 2
    GROUP BY tt.TagName, tt.QuestionCount
),
UserBadges AS (
    SELECT
        u.Id            AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b
      ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestions,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS TotalAnswers,
        COUNT(DISTINCT c.Id)                               AS TotalComments,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS TotalUpVotes,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS TotalDownVotes
    FROM Users u
    LEFT JOIN Posts    p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId      = u.Id
    LEFT JOIN Votes    v ON v.UserId      = u.Id
    GROUP BY u.Id
),
RecentExperts AS (
    SELECT DISTINCT
        tp.TagName,
        tp.OwnerUserId AS UserId
    FROM TagPosts tp
    WHERE tp.CreatedDate >= DATE '2024-10-01' - INTERVAL '30 days'
)
SELECT
    ts.TagName,
    ts.QuestionCount,
    ts.AnswerCount,
    ROUND(ts.AvgAnswerScore, 2)     AS AvgAnswerScore,
    ROUND(ts.AvgQuestionScore, 2)   AS AvgQuestionScore,
    ts.MaxQuestionViews,
    ub.DisplayName      AS TopExpert,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.TotalComments,
    ua.TotalUpVotes,
    ua.TotalDownVotes
FROM TagStats ts
LEFT JOIN RecentExperts re
  ON re.TagName = ts.TagName
LEFT JOIN UserBadges ub
  ON ub.UserId = re.UserId
LEFT JOIN UserActivity ua
  ON ua.UserId = re.UserId
ORDER BY
    ts.QuestionCount DESC,
    ts.AnswerCount   DESC,
    ub.GoldBadges    DESC;