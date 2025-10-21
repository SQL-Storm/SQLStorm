WITH ActiveUsers AS (
    SELECT u.Id AS UserId,
           u.Reputation,
           u.CreationDate,
           COUNT(DISTINCT p.Id) AS PostCount,
           SUM(p.Score) AS TotalScore,
           AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount END) AS AvgQuestionViews
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000 AND p.CreationDate > DATE '2010-01-01'
    GROUP BY u.Id, u.Reputation, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) > 50
),
BadgeSummary AS (
    SELECT b.UserId,
           COUNT(*) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges
    FROM Badges b
    WHERE b.Class IN (1, 2) AND b.TagBased = TRUE
    GROUP BY b.UserId
),
VoteAnalysis AS (
    SELECT v.PostId,
           COUNT(*) AS UpVotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3) AND v.CreationDate > DATE '2020-01-01'
    GROUP BY v.PostId
),
TagPopularity AS (
    SELECT t.TagName,
           COUNT(p.Id) AS QuestionCount,
           ROW_NUMBER() OVER (ORDER BY COUNT(p.Id) DESC) AS TagRank
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 1000
),
ComplexJoins AS (
    SELECT au.UserId,
           au.Reputation,
           au.PostCount,
           au.TotalScore,
           au.AvgQuestionViews,
           bs.GoldBadges,
           bs.SilverBadges,
           SUM(va.UpVotes) AS TotalUpVotes,
           AVG(va.DownVotes) AS AvgDownVotes,
           STRING_AGG(DISTINCT tp.TagName, ', ') AS TopTags
    FROM ActiveUsers au
    LEFT JOIN BadgeSummary bs ON au.UserId = bs.UserId
    LEFT JOIN Posts p ON au.UserId = p.OwnerUserId
    LEFT JOIN VoteAnalysis va ON p.Id = va.PostId
    LEFT JOIN TagPopularity tp ON p.Tags LIKE '%' || tp.TagName || '%'
    WHERE tp.TagRank <= 10
    GROUP BY au.UserId,
             au.Reputation,
             au.PostCount,
             au.TotalScore,
             au.AvgQuestionViews,
             bs.GoldBadges,
             bs.SilverBadges
)
SELECT cj.UserId,
       cj.Reputation,
       cj.PostCount,
       cj.TotalScore,
       cj.AvgQuestionViews,
       cj.GoldBadges,
       cj.SilverBadges,
       cj.TotalUpVotes,
       cj.AvgDownVotes,
       cj.TopTags,
       (SELECT COUNT(*) FROM Comments c WHERE c.UserId = cj.UserId) AS CommentCount,
       (SELECT MAX(ph.CreationDate) FROM PostHistory ph WHERE ph.UserId = cj.UserId) AS LastEditDate
FROM ComplexJoins cj
WHERE cj.TotalUpVotes > 100
ORDER BY cj.Reputation DESC, cj.TotalScore DESC
LIMIT 100;