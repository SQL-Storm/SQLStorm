WITH RecursiveTagHits AS (
    SELECT
        pt.Id AS PostId,
        TRIM(regexp_split_to_table(
            regexp_replace(coalesce(pt.Tags, ''), '[<>]', ' ', 'g'), ' ')) AS SingleTag
    FROM Posts pt
    WHERE pt.PostTypeId = 1
),
UserMostActivePosts AS (
    SELECT
        p.OwnerUserId,
        p.Id AS PostId,
        p.Score,
        p.CreationDate,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate ASC) AS user_rnk
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
      AND p.PostTypeId IN (1, 2)
),
AggregatedBadges AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
CTVtVoteDensity AS (
    SELECT
        p.OwnerUserId,
        vt.Name                        AS VoteTypeName,
        COUNT(v.Id)                   AS VoteCount,
        AVG(ABS(v.BountyAmount))      AS AvgBountyAmount,
        COUNT(v.Id) FILTER (WHERE v.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days') AS RecRecentVotes
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    JOIN Posts p ON p.Id = v.PostId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, vt.Name
),
ExclusiveComments AS (
    SELECT 
      c.PostId,
      COUNT(CASE WHEN c.UserId IS NULL THEN 1 END) AS AnonymousCommentsCount,
      COUNT(c.Id) AS TotalCommentsCount,
      COUNT(DISTINCT c.UserId) AS DistinctCommenters
    FROM Comments c
    GROUP BY c.PostId
),
QuestionsWithAnswers AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        COALESCE(MIN(a.CreationDate), CAST('1900-01-01' AS timestamp)) AS FirstAnswerCondition,
        COUNT(a.Id) FILTER (WHERE a.Score > q.Score / NULLIF(q.AnswerCount,0)) AS BeatsQuestionAnswerCount
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.OwnerUserId, q.Score, q.ViewCount, q.AnswerCount
),
PostTopPerUser AS (
    SELECT
        OwnerUserId,
        MAX(Score) AS Score,
        FIRST_VALUE(Id) OVER (PARTITION BY OwnerUserId ORDER BY Score DESC, ViewCount DESC) AS PostId
    FROM Posts
    WHERE OwnerUserId IS NOT NULL AND PostTypeId IN (1,2)
    GROUP BY OwnerUserId, Id, Score, ViewCount
),
StrokePosts AS (
  SELECT
    OwnerUserId,
    COUNT(*) FILTER (WHERE PostTypeId = 1) AS QuestionCount,
    ROUND(AVG(CAST(ViewCount AS numeric)), 2) AS AverageViews
  FROM Posts
  GROUP BY OwnerUserId
),
CommentSumm AS (
  SELECT 
    c_avg.UserId,
    ROUND(AVG(COALESCE(c_avg.anon_cnt,0)), 2) AS AnonymousCommentsAvg,
    ROUND(AVG(c_avg.total_cnt), 2) AS TotalCmtrSum
  FROM (
    SELECT
        UserId,
        COUNT(CASE WHEN UserId IS NULL THEN 1 END) AS anon_cnt,
        COUNT(*) AS total_cnt,
        PostId
    FROM Comments 
    GROUP BY UserId, PostId
  ) c_avg
  GROUP BY c_avg.UserId
)
SELECT 
    u.Id AS UserId,
    COALESCE(u.DisplayName, '[anonymous]') AS DisplayName,
    u.Reputation,
    ab.GoldBadges,
    ab.SilverBadges,
    ab.BronzeBadges,
    (u.WebsiteUrl IS NOT NULL AND LENGTH(TRIM(u.WebsiteUrl)) <> 0) AS HasWebsite,
    pvdt.VoteTypeName,
    pvdt.VoteCount,
    pvdt.AvgBountyAmount,
    ump.Score AS TopPostScore,
    ump.PostId AS TopPostId,
    strokePosts.QuestionCount,
    strokePosts.AverageViews,
    commentSumm.AnonymousCommentsAvg,
    NULL AS BuiltInScore,
    (EXISTS (
        SELECT 1 FROM Posts p2
        WHERE p2.OwnerUserId = u.Id
          AND EXISTS (
              SELECT 1 FROM PostLinks pl
              WHERE pl.PostId = p2.Id
                AND pl.LinkTypeId = (SELECT Id FROM LinkTypes WHERE Name = 'Duplicate' LIMIT 1)
                -- behaviourality.DuplicatesSet referenced in original is undefined; replace with a sensible placeholder condition
                AND pl.RelatedPostId IS NOT NULL
          )
    )) AS HasTopExamplesLinkedDuplicates
FROM Users u
LEFT JOIN AggregatedBadges ab 
    ON ab.UserId = u.Id
LEFT JOIN CTVtVoteDensity pvdt 
    ON pvdt.OwnerUserId = u.Id
LEFT JOIN PostTopPerUser ump 
    ON ump.OwnerUserId = u.Id
LEFT JOIN StrokePosts strokePosts
    ON strokePosts.OwnerUserId = u.Id
LEFT JOIN CommentSumm commentSumm
    ON commentSumm.UserId = u.Id;