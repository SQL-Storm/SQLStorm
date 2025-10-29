SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ViewCount > 1000 THEN p.Id END) as HighViewQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 10 THEN p.Id END) as HighScoreAnswers,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as TotalQuestionScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as TotalAnswerScore,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) as AvgQuestionScore,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) as AvgAnswerScore,
    COUNT(DISTINCT b.Id) as BadgesReceived,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
    COUNT(DISTINCT c.Id) as CommentsMade,
    COUNT(DISTINCT ph.Id) as PostHistoryEntries,
    COUNT(DISTINCT pl.Id) as PostLinks,
    STRING_AGG(DISTINCT t.TagName, ', ' ORDER BY t.TagName) as UserTags,
    MAX(p.CreationDate) as LastPostDate,
    MIN(p.CreationDate) as FirstPostDate,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 0 THEN 
            DATE_PART('day', MAX(p.CreationDate) - MIN(p.CreationDate)) 
        ELSE 0 
    END as ActiveDays,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Posts p2 
         WHERE p2.OwnerUserId = u.Id 
           AND p2.PostTypeId = 1 
           AND p2.Score > 100 
           AND (p2.ClosedDate IS NULL OR p2.ClosedDate > DATE '2023-01-01')
           AND EXISTS (
               SELECT 1 
               FROM Votes v 
               WHERE v.PostId = p2.Id 
                 AND v.VoteTypeId IN (2, 3)
           )
        ), 0
    ) as HighlyVotedQuestions,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Posts p3 
         WHERE p3.OwnerUserId = u.Id 
           AND p3.PostTypeId = 2 
           AND (p3.AcceptedAnswerId IS NOT NULL OR p3.Score > 50)
           AND EXISTS (
               SELECT 1 
               FROM PostHistory ph2 
               WHERE ph2.PostId = p3.Id 
                 AND ph2.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
                 AND ph2.CreationDate > DATE '2023-01-01'
           )
        ), 0
    ) as RecentEditedAnswers,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Veteran' 
        WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Experienced' 
        WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Active' 
        ELSE 'New' 
    END as UserActivityLevel,
    ROUND(
        COALESCE(
            (COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) * 100.0 / 
             NULLIF(COUNT(DISTINCT p.Id), 0)), 0
        ), 2
    ) as AnswerPercentage,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) > 0 THEN 
            'GoldBadgeHolder' 
        WHEN COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) > 0 THEN 
            'SilverBadgeHolder' 
        WHEN COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) > 0 THEN 
            'BronzeBadgeHolder' 
        ELSE 'NoBadges' 
    END as BadgeStatus,
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM Posts p4 
            WHERE p4.OwnerUserId = u.Id 
              AND p4.PostTypeId = 1 
              AND p4.Score < 0
        ) THEN 'NegativeScoreQuestions' 
        ELSE 'NoNegativeScoreQuestions' 
    END as QuestionScoreStatus,
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM Posts p5 
            WHERE p5.OwnerUserId = u.Id 
              AND p5.PostTypeId = 2 
              AND p5.Score < 0
        ) THEN 'NegativeScoreAnswers' 
        ELSE 'NoNegativeScoreAnswers' 
    END as AnswerScoreStatus,
    ROW_NUMBER() OVER (ORDER BY 
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) + 
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) DESC
    ) as ScoreRank,
    RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as ActivityRank,
    DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT b.Id) DESC) as BadgeRank,
    NTILE(10) OVER (ORDER BY COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0)) as ScoreDecile
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
LEFT JOIN PostLinks pl ON u.Id = pl.Id
LEFT JOIN (
    SELECT DISTINCT 
        Posts.OwnerUserId,
        TRIM(t.TagName) as TagName
    FROM Posts
    JOIN (
        SELECT Id, unnest(string_to_array(Tags, '<>')) as TagName
        FROM Posts 
        WHERE Tags IS NOT NULL and Tags != ''
    ) t ON Posts.Id = t.Id
    JOIN Tags ON TRIM(t.TagName) = Tags.TagName
    WHERE Posts.OwnerUserId IS NOT NULL
) t ON u.Id = t.OwnerUserId
WHERE u.Reputation >= 100
  AND u.CreationDate >= DATE '2020-01-01'
  AND (
    EXISTS (
        SELECT 1 
        FROM Posts p_temp 
        WHERE p_temp.OwnerUserId = u.Id 
          AND p_temp.CreationDate >= DATE '2023-01-01'
    )
    OR EXISTS (
        SELECT 1 
        FROM Badges b_temp 
        WHERE b_temp.UserId = u.Id 
          AND b_temp.Date >= DATE '2023-01-01'
    )
  )
  AND NOT EXISTS (
    SELECT 1 
    FROM Posts p2 
    WHERE p2.OwnerUserId = u.Id 
      AND p2.PostTypeId = 2 
      AND p2.Score = 0 
      AND p2.CreationDate < DATE '2022-01-01'
  )
  AND COALESCE(
    (SELECT COUNT(*) 
     FROM Posts p3 
     WHERE p3.OwnerUserId = u.Id 
       AND p3.PostTypeId = 1 
       AND p3.Score > 100 
       AND p3.LastActivityDate > DATE '2023-06-01'
    ), 0
  ) > 0
  AND COALESCE(u.Views, 0) > 500
  AND (
    u.Location IS NOT NULL 
    AND u.Location != '' 
    AND u.Location != ' '
  )
  AND (
    u.WebsiteUrl IS NULL 
    OR u.WebsiteUrl = '' 
    OR u.WebsiteUrl LIKE '%stackoverflow%'
  )
GROUP BY 
    u.Id, 
    u.DisplayName, 
    u.Reputation,
    CASE 
        WHEN u.Location IS NOT NULL AND u.Location != '' AND u.Location != ' ' THEN 1 
        ELSE 0 
    END,
    CASE 
        WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' OR u.WebsiteUrl LIKE '%stackoverflow%' THEN 1 
        ELSE 0 
    END
HAVING 
    COUNT(DISTINCT p.Id) > 0
    AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0
    AND (
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ViewCount > 1000 THEN p.Id END) > 0
        OR COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.Score >= 10 THEN p.Id END) > 0
    )
    AND (
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) > 500
        OR COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) > 1000
    )
    AND (
        COUNT(DISTINCT b.Id) > 20
        OR EXISTS (
            SELECT 1 
            FROM Badges b2 
            WHERE b2.UserId = u.Id 
              AND b2.Class = 1
        )
    )
    AND (
        COUNT(DISTINCT CASE WHEN c.Id IS NOT NULL THEN c.Id END) > 50
        OR EXISTS (
            SELECT 1 
            FROM PostHistory ph2 
            WHERE ph2.UserId = u.Id 
              AND ph2.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
        )
    )
    AND CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 THEN 
            AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END)
        ELSE 0 
    END > 3
    AND CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 0 THEN 
            AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END)
        ELSE 0 
    END > 1
    AND (
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) >= 3
        OR EXISTS (
            SELECT 1 
            FROM Posts p3 
            WHERE p3.OwnerUserId = u.Id 
              AND p3.PostTypeId = 1 
              AND p3.ViewCount > 5000
        )
    )
ORDER BY 
    (COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) + COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0)) DESC,
    BadgesReceived DESC,
    Reputation DESC
LIMIT 100 OFFSET 50;