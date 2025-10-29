-- {"query": "2269.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1830} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.CreationDate,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p2.Id) filter (where p2.PostTypeId = 2) as AnswerCount,
        coalesce(sum(vt2.VoteCount),0) as TotalVotesReceived,
        max(p.CreationDate) as LastPostDate,
        row_number() over (partition by u.Id order by max(p.CreationDate) desc nulls last) as LastActivityRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Posts p2 on p2.OwnerUserId = u.Id
    left join (
        select
            PostId,
            sum(case when VoteTypeId = 2 then 1 else 0 end) -
            sum(case when VoteTypeId = 3 then 1 else 0 end) as NetVotes
        from Votes
        group by PostId
    ) vt on vt.PostId = p.Id
    left join LATERAL (
        select count(*) as VoteCount from Votes v where v.PostId = p.Id
    ) vt2 on true
    group by u.Id, u.DisplayName, u.CreationDate, u.Reputation
),
TopBadgeUsers as (
    select
        b.UserId,
        count(*) as BadgeCount,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
PostLinkAggregates as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Linked') as LinkedCount,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Duplicate') as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.OwnerUserId,
        q.Title,
        q.CreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        coalesce(a.AnswerCount, 0) as AnswerCount,
        coalesce(a.MaxAnswerScore, 0) as MaxAnswerScore,
        coalesce(topAnswer.OwnerUserId, -1) as TopAnswerOwnerUserId,
        topAnswer.Score as TopAnswerScore
    from Posts q
    left join (
        select
            ParentId,
            count(*) as AnswerCount,
            max(Score) as MaxAnswerScore
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) a on a.ParentId = q.Id
    left join lateral (
        select p2.OwnerUserId, p2.Score
        from Posts p2
        where p2.ParentId = q.Id
        order by p2.Score desc nulls last
        limit 1
    ) topAnswer on true
    where q.PostTypeId = 1
),
RankedPosts as (
    select
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last, p.CreationDate desc) as UserPostRank
    from Posts p
    where p.PostTypeId in (1, 2)
),
ComplexJoinResult as (
    select
        ru.UserId,
        ru.DisplayName,
        ru.Reputation,
        ru.QuestionCount,
        ru.AnswerCount,
        ru.TotalVotesReceived,
        coalesce(tb.BadgeCount,0) as BadgeCount,
        coalesce(tb.GoldBadges,0) as GoldBadgeCount,
        coalesce(tb.SilverBadges,0) as SilverBadgeCount,
        coalesce(tb.BronzeBadges,0) as BronzeBadgeCount,
        qa.QuestionId,
        qa.Title as QuestionTitle,
        qa.Score as QuestionScore,
        qa.ViewCount as QuestionViewCount,
        qa.AnswerCount,
        qa.MaxAnswerScore,
        qa.TopAnswerOwnerUserId,
        rp.Id as TopPostId,
        rp.Score as TopPostScore,
        coalesce(pl.LinkedCount,0) as LinkedCount,
        coalesce(pl.DuplicateCount,0) as DuplicateCount,
        case 
            when rp.Score is null then null
            when rp.Score >= 50 then 'High'
            when rp.Score >= 20 then 'Medium'
            else 'Low'
        end as PostScoreCategory,
        length(coalesce(rp.Tags, '')) - length(replace(coalesce(rp.Tags, ''), '<', '')) as TagCount,
        case 
            when rp.Tags is null then 'No Tags'
            when rp.Tags like '%<sql>%' then 'Contains SQL Tag'
            else 'Other Tags'
        end as TagCategory
    from RecursiveUserActivity ru
    left join TopBadgeUsers tb on tb.UserId = ru.UserId
    left join QuestionAnswerStats qa on qa.OwnerUserId = ru.UserId
    left join RankedPosts rp on rp.OwnerUserId = ru.UserId and rp.UserPostRank = 1
    left join PostLinkAggregates pl on pl.PostId = rp.Id
    where ru.LastActivityRank <= 500
)
select 
    UserId,
    DisplayName,
    Reputation,
    QuestionCount,
    AnswerCount,
    TotalVotesReceived,
    BadgeCount,
    GoldBadgeCount,
    SilverBadgeCount,
    BronzeBadgeCount,
    QuestionId,
    QuestionTitle,
    QuestionScore,
    QuestionViewCount,
    AnswerCount as AnswersOnQuestion,
    MaxAnswerScore,
    TopAnswerOwnerUserId,
    TopPostId,
    TopPostScore,
    LinkedCount,
    DuplicateCount,
    PostScoreCategory,
    TagCount,
    TagCategory,
    -- Correlated subquery computing average answer score per user for answers posted after user's first question creation
    (select avg(p.AnswerScore) from (
        select p2.Score as AnswerScore
        from Posts p2
        where p2.PostTypeId = 2 and p2.OwnerUserId = ComplexJoinResult.UserId 
          and p2.CreationDate > (select min(CreationDate) from Posts where OwnerUserId = ComplexJoinResult.UserId and PostTypeId = 1)
    ) p) as AvgAnswerScoreAfterFirstQuestion,
    -- Window function calculating running sum of BadgeCount over ordered Reputation descending
    sum(BadgeCount) over (order by Reputation desc rows between unbounded preceding and current row) as RunningBadgeSum,
    -- Complex predicate example with NULL logic and string manipulations
    case 
        when (Position('sql' in lower(QuestionTitle)) > 0 and GoldBadgeCount > 0) or DuplicateCount is null then 'Focus on SQL'
        when (TagCount > 3 and SilverBadgeCount >= 5) then 'Active Tag User'
        when BadgeCount is null or BadgeCount = 0 then 'New or Inactive'
        else 'Regular User'
    end as UserCategory
from ComplexJoinResult
where QuestionScore > 10 or BronzeBadgeCount > 10
union
select
    null as UserId,
    'Community' as DisplayName,
    null as Reputation,
    null as QuestionCount,
    null as AnswerCount,
    null as TotalVotesReceived,
    null as BadgeCount,
    null as GoldBadgeCount,
    null as SilverBadgeCount,
    null as BronzeBadgeCount,
    null as QuestionId,
    null as QuestionTitle,
    null as QuestionScore,
    null as QuestionViewCount,
    null as AnswersOnQuestion,
    null as MaxAnswerScore,
    null as TopAnswerOwnerUserId,
    null as TopPostId,
    null as TopPostScore,
    null as LinkedCount,
    null as DuplicateCount,
    null as PostScoreCategory,
    null as TagCount,
    null as TagCategory,
    null as AvgAnswerScoreAfterFirstQuestion,
    null as RunningBadgeSum,
    'Community aggregate row' as UserCategory
order by Reputation desc nulls last, BadgeCount desc nulls last, UserId nulls last
limit 100;