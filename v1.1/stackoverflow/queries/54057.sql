WITH
GoldUsers AS (
    SELECT DISTINCT UserId
    FROM Badges
    WHERE Class = 1
),
RecentQuestions AS (
    SELECT
        p.Id,
        p.Score,
        p.Tags,
        p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Score > 0
      AND p.CreationDate >= DATE '2024-10-01'
      AND p.OwnerUserId IN (SELECT UserId FROM GoldUsers)
),
QuestionTags AS (
    SELECT
        rq.Id,
        rq.OwnerUserId,
        rq.Score,
        t.tag
    FROM RecentQuestions rq,
    LATERAL (
        SELECT trim(both ' ' FROM regexp_split_to_table(
            -- remove leading '<' and trailing '>' if present
            CASE
              WHEN rq.Tags LIKE '<%' AND rq.Tags LIKE '%>' THEN substr(rq.Tags, 2, char_length(rq.Tags) - 2)
              ELSE rq.Tags
            END,
            ' ><'
        )) AS tag
    ) t
)
SELECT
    qt.tag,
    COUNT(DISTINCT qt.Id)          AS QuestionCount,
    AVG(qt.Score)                  AS AvgScore,
    COUNT(DISTINCT qt.OwnerUserId) AS GoldUserCount,
    RANK() OVER (ORDER BY AVG(qt.Score) DESC, COUNT(DISTINCT qt.Id) DESC) AS Rank
FROM QuestionTags qt
GROUP BY qt.tag
ORDER BY Rank
FETCH FIRST 20 ROWS ONLY;