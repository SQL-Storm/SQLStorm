-- {"query": "2900.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1077} 
with RecursiveUserPosts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        array_length(string_to_array(coalesce(p.Tags, ''), '><'),1) as TagCount
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000

    union all

    select 
        rup.UserId,
        rup.DisplayName,
        p2.Id as PostId,
        p2.PostTypeId,
        p2.Score,
        p2.ViewCount,
        p2.CreationDate,
        p2.Title,
        p2.Tags,
        array_length(string_to_array(coalesce(p2.Tags, ''), '><'),1) as TagCount
    from RecursiveUserPosts rup
    join Posts p on p.Id = rup.PostId and p.PostTypeId = 1 -- questions only
    join Posts p2 on p2.ParentId = p.Id -- answers to those questions
    where rup.TagCount > 1 and p2.Score > 0
),
RankedAnswers as (
    select 
        PostId,
        OwnerUserId,
        Score,
        CreationDate,
        row_number() over (partition by OwnerUserId order by Score desc, CreationDate asc) as AnswerRank
    from Posts
    where PostTypeId = 2 and OwnerUserId is not null
),
TopAnswers as (
    select * from RankedAnswers where AnswerRank <= 3
),
UserBadgeSummary as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        bool_or(b.TagBased) as HasTagBasedBadge,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
CloseReasonDesc as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
)
select distinct 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    coalesce(us.GoldBadges,0) as GoldBadges,
    coalesce(us.SilverBadges,0) as SilverBadges,
    coalesce(us.BronzeBadges,0) as BronzeBadges,
    us.HasTagBasedBadge,
    (select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1) as QuestionCount,
    (select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 2) as AnswerCount,
    (select avg(p.Score) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 2) as AvgAnswerScore,
    (select string_agg(distinct t.TagName, ', ') from Tags t 
        join Posts pt on (pt.Tags is not null and position('<' || t.TagName || '>' in pt.Tags) > 0)
        where pt.OwnerUserId = u.Id
        order by count(*) desc limit 5) as TopTags,
    array_to_string(array(
        select concat_ws(': ', ph.CreationDate::date, crd.CloseReasonName) from CloseReasonDesc crd 
        join PostHistory ph on ph.PostId = crd.PostId and ph.CreationDate = crd.CloseDate
        join Posts p on p.Id = ph.PostId
        where p.OwnerUserId = u.Id
        order by ph.CreationDate desc
        limit 3
    ), '; ') as RecentCloseReasons,
    ta.PostId as TopAnswerId,
    ta.Score as TopAnswerScore,
    ta.CreationDate as TopAnswerDate,
    concat_ws(
        ' | ',
        'Score*: ', coalesce(ta.Score,0),
        'Views: ', coalesce(pv.ViewCount,0),
        'Tags: ', coalesce(ta.Tags, '')
    ) as TopAnswerSummary
from Users u
left join UserBadgeSummary us on us.UserId = u.Id
left join TopAnswers ta on ta.OwnerUserId = u.Id
left join Posts pv on pv.Id = ta.PostId
where u.Reputation > 1000
and (
    exists (
        select 1 from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1 and p.ViewCount > 10000
    )
    or us.GoldBadges > 0
)
order by u.Reputation desc, us.GoldBadges desc nulls last, AvgAnswerScore desc nulls last
limit 100;