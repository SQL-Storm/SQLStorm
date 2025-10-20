WITH question_posts AS (
    SELECT p.Id, p.Score, p.OwnerUserId, p.Tags
    FROM Posts p
    WHERE p.PostTypeId = 1
),
tag_split AS (
    SELECT qp.Id,
           TRIM(BOTH '<>' FROM UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM qp.Tags), '><'))) AS TagName,
           qp.Score,
           qp.OwnerUserId
    FROM question_posts qp
),
tag_vote_stats AS (
    SELECT ts.TagName,
           COUNT(*)                               AS QuestionCount,
           AVG(ts.Score)                          AS AvgScore,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM tag_split ts
    LEFT JOIN Votes v ON v.PostId = ts.Id
    GROUP BY ts.TagName
    HAVING COUNT(*) >= 100
),
top_tag_user AS (
    SELECT tvs.TagName,
           pu.DisplayName      AS TopUser,
           pu.Reputation       AS TopUserRep,
           p_owner.OwnerUserId
    FROM tag_vote_stats tvs
    JOIN LATERAL (
        SELECT p.OwnerUserId
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND EXISTS (
              SELECT 1 FROM tag_split t2
              WHERE t2.TagName = tvs.TagName
                AND t2.Id = p.Id
          )
        ORDER BY p.OwnerUserId
        LIMIT 1
    ) p_owner ON TRUE
    JOIN Users pu ON pu.Id = p_owner.OwnerUserId
)
SELECT tvs.TagName,
       tvs.QuestionCount,
       tvs.AvgScore,
       tvs.UpVotes,
       tvs.DownVotes,
       ROW_NUMBER() OVER (ORDER BY tvs.AvgScore DESC) AS AvgScoreRank,
       tut.TopUser,
       tut.TopUserRep
FROM tag_vote_stats tvs
JOIN top_tag_user tut ON tut.TagName = tvs.TagName
GROUP BY tvs.TagName, tvs.QuestionCount, tvs.AvgScore, tvs.UpVotes, tvs.DownVotes, tut.TopUser, tut.TopUserRep
ORDER BY tvs.AvgScore DESC
LIMIT 10;