-- {"query": "24093.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 4342} 

WITH recent_votes AS (
  SELECT p.Id AS PostId,
         p.OwnerUserId,
         p.PostTypeId,
         SUM(CASE
                WHEN v.VoteTypeId = 2 THEN 1
                WHEN v.VoteTypeId = 3 THEN -1
                ELSE 0
              END) AS NetScore
  FROM Posts p
  JOIN Votes v ON p.Id = v.PostId
  WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '90 days'
  GROUP BY p.Id, p.OwnerUserId, p.PostTypeId
),
user_contrib AS (
  SELECT u.Id          AS UserId,
         COALESCE(u.DisplayName, 'Community') AS DisplayName,
         u.Reputation,
         COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
         COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersGiven,
         COUNT(DISTINCT CASE WHEN c.Id IS NOT NULL THEN c.Id END) AS CommentsMade,
         SUM(rv.NetScore) FILTER (WHERE rv.NetScore IS NOT NULL) AS VoteScore,
         COUNT(DISTINCT tagname) FILTER (WHERE tagname IS NOT NULL) AS DistinctTagsUsed
  FROM Users u
  LEFT JOIN Posts p      ON u.Id = p.OwnerUserId
  LEFT JOIN Comments c   ON u.Id = c.UserId
  LEFT JOIN recent_votes rv
          ON u.Id = rv.OwnerUserId
  LEFT JOIN LATERAL (
        SELECT unnest(string_to_array(p.Tags, '><')) AS tagname
        WHERE p.Tags IS NOT NULL
      ) HT ON TRUE
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
top_users AS (
  SELECT uc.*,
         RANK() OVER (ORDER BY VoteScore DESC, QuestionsAsked DESC) AS Rnk
  FROM user_contrib uc
),
tag_list AS (
  SELECT TagName FROM Tags
  UNION ALL
  SELECT unnest(string_to_array(p.Tags, '><')) AS TagName
  FROM Posts p
  WHERE p.PostTypeId = 1
),
tag_activity AS (
  SELECT tl.TagName,
         COUNT(*)                     AS TotalTagPosts,
         AVG(sa)                      AS AvgNetScore
  FROM tag_list tl
  LEFT JOIN Posts p
          ON p.Tags LIKE CONCAT('%', tl.TagName, '%')
  LEFT JOIN recent_votes rv
          ON p.Id = rv.PostId
  CROSS JOIN LATERAL (SELECT rv.NetScore AS sa) AS SA
  GROUP BY tl.TagName
),
vw_tags AS (
  SELECT TagName,
         TotalTagPosts,
         AvgNetScore
  FROM tag_activity
  WHERE TotalTagPosts > 10
)
SELECT tu.UserId,
       tu.DisplayName,
       tu.Reputation,
       tu.QuestionsAsked,
       tu.AnswersGiven,
       tu.CommentsMade,
       tu.VoteScore,
       tv.TagName,
       tv.TotalTagPosts,
       tv.AvgNetScore,
       tu.Rnk AS UserRank
FROM top_users tu
LEFT JOIN LATERAL (
    SELECT TagName,
           TotalTagPosts,
           AvgNetScore
    FROM vw_tags
    WHERE TagName IN (
        SELECT unnest(
               string_to_array(
                 COALESCE(
                   (SELECT p.Tags
                    FROM Posts p
                    WHERE p.OwnerUserId = tu.UserId AND p.PostTypeId = 1
                    ORDER BY CreationDate DESC LIMIT 1), ''
                 ), '><')
            )
    )
    ORDER BY TotalTagPosts DESC
    LIMIT 3
) tv ON true
WHERE tu.Rnk <= 50
ORDER BY tu.Rnk, tv.TotalTagPosts DESC;
