WITH TagAnswers AS (
    SELECT p.ParentId AS question_id,
           p.OwnerUserId,
           p.Score,
           -- convert tags like '<tag1><tag2>' into array using standard functions
           regexp_split_to_array(substring(q.Tags FROM 2 FOR length(q.Tags) - 2), '><') AS tags
    FROM Posts p
    JOIN Posts q ON p.ParentId = q.Id
    WHERE p.PostTypeId = 2
      AND q.PostTypeId = 1
      AND q.Tags IS NOT NULL
),
UnnestedTags AS (
    SELECT ta.question_id,
           ta.OwnerUserId,
           ta.Score,
           t.tag
    FROM TagAnswers ta,
         unnest(ta.tags) AS t(tag)
),
TagUserStats AS (
    SELECT tag,
           OwnerUserId,
           COUNT(*) AS num_answers,
           AVG(Score) AS avg_score,
           SUM(Score) AS total_score
    FROM UnnestedTags
    GROUP BY tag, OwnerUserId
    HAVING COUNT(*) > 5
),
TopUsersPerTag AS (
    SELECT tag,
           OwnerUserId,
           num_answers,
           avg_score,
           total_score,
           RANK() OVER (PARTITION BY tag ORDER BY num_answers DESC, avg_score DESC, total_score DESC) AS rank
    FROM TagUserStats
),
UserDetails AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           u.CreationDate,
           COUNT(DISTINCT b.Id) AS badges,
           COUNT(DISTINCT c.Id) AS comments
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
)
SELECT tpt.tag,
       ud.DisplayName,
       tpt.num_answers,
       tpt.avg_score,
       tpt.total_score,
       ud.Reputation,
       ud.badges,
       ud.comments
FROM TopUsersPerTag tpt
JOIN UserDetails ud ON tpt.OwnerUserId = ud.Id
WHERE tpt.rank <= 10
ORDER BY tpt.tag, tpt.rank;