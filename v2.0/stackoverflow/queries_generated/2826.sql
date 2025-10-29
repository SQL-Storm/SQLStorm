-- {"query": "2826.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1020} 
with RecursiveTagHierarchy as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        coalesce(t.ExcerptPostId, 0) as ExcerptPostId,
        coalesce(t.WikiPostId, 0) as WikiPostId,
        0 as Level,
        cast(t.TagName as varchar(1000)) as TagPath
    from Tags t
    where t.IsRequired = 1
    union all
    select 
        c.Id,
        c.TagName,
        c.Count,
        coalesce(c.ExcerptPostId, 0),
        coalesce(c.WikiPostId, 0),
        r.Level + 1,
        r.TagPath || ' > ' || c.TagName
    from Tags c
    join RecursiveTagHierarchy r on c.IsRequired = 1 and c.Id > r.Id and c.Count < r.Count
    where r.Level < 3
), UserStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges,
        coalesce(avg(p.Score), 0) as AvgPostScore,
        max(p.Score) as MaxPostScore,
        count(distinct p.Id) as PostCount,
        row_number() over (order by u.Reputation desc, u.Id) as RankByReputation
    from Users u
    left join Badges b on b.UserId = u.Id
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId in (1,2)
    group by u.Id, u.DisplayName, u.Reputation
), PopularQuestions as (
    select 
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        array_to_string(
            array_agg(distinct pht.Name order by pht.Name), ', '
        ) as HistoryEvents,
        (select count(*) from Comments c where c.PostId = p.Id and (c.Text ~* 'performance|benchmark|slow|optimization')) as RelevantComments,
        lead(p.Score) over (order by p.Score desc) as NextScore,
        lag(p.Score) over (order by p.Score desc) as PrevScore
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id
    left join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    where p.PostTypeId = 1
      and p.Score > 10
      and p.CreationDate > (current_date - interval '3 year')
    group by p.Id, p.OwnerUserId, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.Tags
)
select 
    u.DisplayName,
    u.Reputation,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    u.TagBasedBadges,
    round(u.AvgPostScore,2) as AvgPostScore,
    u.MaxPostScore,
    u.PostCount,
    pq.Id as TopQuestionId,
    pq.Title as TopQuestionTitle,
    pq.Score as TopQuestionScore,
    pq.ViewCount as TopQuestionViews,
    pq.AnswerCount as TopQuestionAnswers,
    pq.HistoryEvents,
    pq.RelevantComments,
    case 
        when pq.NextScore is null then null
        else concat('Next higher score: ', pq.NextScore)
    end as NextHigherScore,
    case
        when pq.PrevScore is null then null
        else concat('Previous lower score: ', pq.PrevScore)
    end as PreviousLowerScore,
    rth.TagPath as SampleTagPath,
    rth.Level as SampleTagLevel
from UserStats u
left join lateral (
    select p.*
    from PopularQuestions p
    where p.OwnerUserId = u.UserId
    order by p.Score desc, p.CreationDate desc
    limit 1
) pq on true
left join RecursiveTagHierarchy rth on strpos(pq.Tags, rth.TagName) > 0
where u.PostCount > 20
  and u.Reputation > 5000
  and (u.GoldBadges + u.SilverBadges + u.BronzeBadges) > 5
order by u.Reputation desc, u.PostCount desc
limit 50;