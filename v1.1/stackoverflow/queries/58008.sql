WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersProvided,
        AVG(p.Score) AS AvgPostScore,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotesReceived,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS Upvotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 8 THEN v.Id END) AS BountiesStarted,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        (SELECT STRING_AGG(top_three_tags.TagName, ', ' ORDER BY top_three_tags.tag_count DESC)
         FROM (
             SELECT t.TagName, COUNT(*) AS tag_count
             FROM Posts pt
             JOIN Tags t ON pt.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
             WHERE pt.OwnerUserId = u.Id
             GROUP BY t.TagName
             ORDER BY tag_count DESC
             LIMIT 3
         ) AS top_three_tags) AS TopTags,
        (SELECT COUNT(*) 
         FROM PostHistory ph 
         WHERE ph.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id) 
           AND ph.PostHistoryTypeId = 10) AS ClosedPosts
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.CreationDate
),
RankedUsers AS (
    SELECT 
        UserId,
        Reputation,
        TotalPosts,
        QuestionsAsked,
        AnswersProvided,
        AvgPostScore,
        TotalComments,
        TotalVotesReceived,
        Upvotes,
        BountiesStarted,
        TotalBadges,
        GoldBadges,
        TopTags,
        ClosedPosts,
        RANK() OVER (ORDER BY Reputation DESC) AS ReputationRank,
        RANK() OVER (ORDER BY TotalPosts DESC) AS ActivityRank
    FROM UserStats
)
SELECT 
    ru.UserId,
    ru.Reputation,
    ru.TotalPosts,
    ru.QuestionsAsked,
    ru.AnswersProvided,
    ru.AvgPostScore,
    ru.TotalComments,
    ru.TotalVotesReceived,
    ru.Upvotes,
    ru.BountiesStarted,
    ru.TotalBadges,
    ru.GoldBadges,
    ru.TopTags,
    ru.ClosedPosts,
    ru.ReputationRank,
    ru.ActivityRank,
    (SELECT COUNT(*) 
     FROM PostLinks pl 
     WHERE pl.LinkTypeId = 3 
       AND pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = ru.UserId)) AS DuplicatePostsLinked,
    (SELECT MAX(CreationDate) 
     FROM Posts 
     WHERE OwnerUserId = ru.UserId) AS LastPostDate,
    (SELECT SUM(AnswerCount) 
     FROM Posts 
     WHERE OwnerUserId = ru.UserId AND PostTypeId = 1) AS TotalAnswersGenerated
FROM RankedUsers ru
WHERE ru.Reputation > 10000
  AND ru.TotalPosts > 50
  AND ru.GoldBadges >= 1
ORDER BY 
    (ru.ReputationRank + ru.ActivityRank) ASC,
    ru.Upvotes DESC
FETCH FIRST 100 ROWS ONLY;