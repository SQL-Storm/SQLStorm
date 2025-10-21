-- {"query": "52004.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 754} 
WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        EXTRACT(YEAR FROM CURRENT_DATE) - EXTRACT(YEAR FROM u.CreationDate) as AccountAgeYears,
        COUNT(DISTINCT b.Id) as TotalBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
        COALESCE(SUM(p.Score), 0) as TotalPostScore,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COALESCE(SUM(v.UpvoteCount), 0) as TotalUpvotesReceived,
        COALESCE(SUM(v.DownvoteCount), 0) as TotalDownvotesReceived,
        COUNT(DISTINCT c.Id) as TotalCommentsReceived,
        COUNT(DISTINCT ph.Id) as EditHistoryCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
    LEFT JOIN (
        SELECT
            PostId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) as UpvoteCount,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) as DownvoteCount
        FROM Votes
        GROUP BY PostId
    ) v ON p.Id = v.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6, 24)
    WHERE u.Reputation > 1000 AND u.CreationDate BETWEEN '2010-01-01' AND '2020-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
RankedUsers AS (
    SELECT
        *,
        ROW_NUMBER() OVER (ORDER BY (Reputation + TotalPostScore + TotalUpvotesReceived - TotalDownvotesReceived + TotalBadges * 10 + EditHistoryCount) / NULLIF(AccountAgeYears, 0) DESC) as Rank,
        NTILE(10) OVER (ORDER BY TotalUpvotesReceived DESC) as UpvoteDecile
    FROM UserStats
)
SELECT
    ru.Id,
    ru.DisplayName,
    ru.Reputation,
    ru.AccountAgeYears,
    ru.TotalBadges,
    ru.GoldBadges,
    ru.SilverBadges,
    ru.BronzeBadges,
    ru.TotalPostScore,
    ru.TotalPosts,
    ru.QuestionCount,
    ru.AnswerCount,
    ru.TotalUpvotesReceived,
    ru.TotalDownvotesReceived,
    ru.TotalCommentsReceived,
    ru.EditHistoryCount,
    ru.Rank,
    ru.UpvoteDecile,
    CASE
        WHEN ru.AnswerCount > ru.QuestionCount THEN 'Answerer'
        WHEN ru.QuestionCount > ru.AnswerCount THEN 'Questioner'
        ELSE 'Balanced'
    END as ContributorType
FROM RankedUsers ru
WHERE ru.Rank <= 500
ORDER BY ru.Rank;