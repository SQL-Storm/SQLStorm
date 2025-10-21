-- {"query": "57009.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 1329} 

WITH RecursiveUserHierarchy AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        1 AS Level
    FROM
        Users u
    WHERE
        u.Reputation > 10000
    UNION ALL
    SELECT
        u.Id,
        u.Reputation,
        u.DisplayName,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        r.Level + 1
    FROM
        Users u
    INNER JOIN
        RecursiveUserHierarchy r
        ON u.AccountId = r.UserId
    WHERE
        u.Reputation > r.Reputation * 0.5
),
HighReputationPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        COALESCE (p.AnswerCount, 0) AS AnswerCount,
        COALESCE (p.CommentCount, 0) AS CommentCount,
        p.ContentLicense
    FROM
        Posts p
    INNER JOIN
        RecursiveUserHierarchy r
        ON p.OwnerUserId = r.UserId
    WHERE
        p.PostTypeId = 1
        AND p.Score > 10
),
TopTags AS (
    SELECT
        Tags,
        STRING_TO_ARRAY(SUBSTRING(Tags FROM 2 FOR LENGTH(Tags) - 2), '><') AS TagArray,
        UNNEST(STRING_TO_ARRAY(SUBSTRING(Tags FROM 2 FOR LENGTH(Tags) - 2), '><')) AS TagName,
        RANK() OVER (PARTITION BY PostId ORDER BY array_length(STRING_TO_ARRAY(SUBSTRING(Tags FROM 2 FOR LENGTH(Tags) - 2), '><'), 1) DESC) AS TagRank
    FROM
        HighReputationPosts
),
TopTagPosts AS (
    SELECT
        PostId,
        TagName,
        Score,
        ViewCount,
        AnswerCount,
        CommentCount
    FROM
        TopTags
    WHERE
        TagRank <= 3
),
TagPerformance AS (
    SELECT
        TagName,
        AVG(Score) AS AvgScore,
        AVG(ViewCount) AS AvgViewCount,
        AVG(AnswerCount) AS AvgAnswerCount,
        AVG(CommentCount) AS AvgCommentCount,
        COUNT(PostId) AS PostCount
    FROM
        TopTagPosts
    GROUP BY
        TagName
    HAVING
        COUNT(PostId) > 10
    ORDER BY
        AvgScore DESC,
        AvgViewCount DESC
),
RecentPosts AS (
    SELECT p.*,
        EXTRACT(EPOCH FROM (NOW() - p.CreationDate)) / 3600 AS HoursSinceCreation
    FROM Posts p WHERE p.PostTypeId in (1,2) AND EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = p.Id AND v.CreationDate > NOW() - INTERVAL '1 week')
    ),
 ActiveTopics as (
     SELECT p.Id AS postID,
         p.Title,
         EXTRACT(EPOCH FROM (NOW() - p.LastActivityDate)) / 3600 AS HoursSinceLastActivity
         from RecentPosts p
         ORDER BY HoursSinceLastActivity DESC
     LIMIT 500

),
PostActivity AS (
  SELECT
      CurrentDistinctPost.Id AS PostId,
      p1.PostTypeId,
      p1.ViewCount AS CurrentViewCount,
      COUNT ( DISTINCT Comment.Id) as CurrentCommentCount,
      coalesce( (select count(p2.Id) from Posts p2
              where p2.OwnerUserId=CurrentDistinctPost.OwnerUserId
              group by p2.OwnerUserId),1) as OwnerUserPostCount,
      COUNT (distinct p1.Id) AS TotalQuestions
  FROM
      Posts as p1
      join ActiveTopics CurrentDistinctPost on CurrentDistinctPost.postID = p1.Id
      LEFT JOIN Comments as Comment on p1.Id=Comment.PostId
  GROUP BY
      CurrentDistinctPost.Id
)
SELECT
    pa.PostId,
    p.Title,
    pa.CurrentViewCount, pa.OwnerUserPostCount,
    pa.CurrentCommentCount,
    pa.TotalQuestions,
    tp.TagName,
    tp.AvgScore,
    tp.AvgViewCount,
    tp.AvgAnswerCount,
    tp.AvgCommentCount,
    tp.PostCount
FROM
    PostActivity pa
INNER JOIN
    Posts p
    ON pa.PostId = p.Id
LEFT JOIN
    TagPerformance tp
    ON p.Tags LIKE CONCAT('%>', tp.TagName, '<%')
ORDER BY
    pa.CurrentViewCount DESC,
    tp.AvgScore DESC;
