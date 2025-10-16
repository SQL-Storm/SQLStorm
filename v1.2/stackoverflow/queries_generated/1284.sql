-- {"query": "1284.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1232} 
with RecursiveTags as (
    select
        p.Id as PostId,
        unnest(string_to_array(coalesce(substring(p.Tags from 2 for char_length(p.Tags) - 2),''), '><')) as Tag
    from Posts p
    where p.PostTypeId = 1
), TopUsers as (
    select u.Id, u.DisplayName, u.Reputation,
        row_number() over (order by u.Reputation desc) as rn
    from Users u
    where u.Reputation > 10000
), RecentBadgeCounts as (
    select b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    where b.Date > now() - interval '365 days'
    group by b.UserId
), QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreated,
        coalesce(a.AnswerCount,0) as AnswerCount,
        coalesce(a.MaxScore,0) as MaxAnswerScore,
        coalesce(a.AvgScore,0)::numeric(10,2) as AvgAnswerScore,
        q.OwnerUserId
    from Posts q
    left join (
        select ParentId,
            count(*) as AnswerCount,
            max(Score) as MaxScore,
            avg(Score) as AvgScore
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) a on q.Id = a.ParentId
    where q.PostTypeId = 1
), LatestPostHistoryEdits as (
    select ph.PostId, ph.UserId, ph.CreationDate, ph.PostHistoryTypeId,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6)
), PostRelations as (
    select pl.PostId, pl.RelatedPostId, lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
), DupicateLinkedQuestions as (
    select q.Id as QuestionId, pr.RelatedPostId, pr.LinkTypeName
    from Posts q
    left join PostRelations pr on pr.PostId = q.Id
    where q.PostTypeId = 1
      and pr.LinkTypeName in ('Duplicate','Linked')
), UserActivityWindows as (
    select
        u.Id as UserId,
        count(distinct p.Id) filter (where p.PostTypeId in (1,2)) as PostsCount,
        count(distinct c.Id) as CommentsCount,
        dense_rank() over (partition by date_trunc('month', p.CreationDate) order by u.Reputation desc) as MonthlyRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.CreationDate >= now() - interval '1 year'
    left join Comments c on c.UserId = u.Id and c.CreationDate >= now() - interval '1 year'
    group by u.Id
)
select
    tu.Id as UserId,
    tu.DisplayName,
    tu.Reputation,
    coalesce(rbc.GoldBadges,0) as GoldBadgesLastYear,
    coalesce(rbc.SilverBadges,0) as SilverBadgesLastYear,
    coalesce(rbc.BronzeBadges,0) as BronzeBadgesLastYear,
    rbc.LastBadgeDate,
    qas.AnswerCount as AnswersForTheirQuestions,
    qas.MaxAnswerScore,
    qas.AvgAnswerScore,
    (select count(*) from DupicateLinkedQuestions dlq where dlq.QuestionId in (
        select p.Id from Posts p where p.OwnerUserId = tu.Id and p.PostTypeId = 1
    )) as LinkedOrDuplicateCount,
    uw.PostsCount,
    uw.CommentsCount,
    uw.MonthlyRank,
    rt.Tag as FrequentTag,
    case
        when tu.DisplayName is null then concat('User#', tu.Id)
        else concat(tu.DisplayName, ' (Reputation: ', tu.Reputation, ')')
    end as UserSummary,
    coalesce(uw.PostsCount,0) * coalesce(qas.AvgAnswerScore,1) / nullif(tu.Reputation,1) as ActivityScore,
    lag(tu.Reputation,1) over (order by tu.Reputation desc) as PrevReputation,
    lead(tu.Reputation,1) over (order by tu.Reputation desc) as NextReputation
from TopUsers tu
left join RecentBadgeCounts rbc on rbc.UserId = tu.Id
left join QuestionAnswerStats qas on qas.OwnerUserId = tu.Id
left join UserActivityWindows uw on uw.UserId = tu.Id
left join lateral (
    select rt.Tag 
    from RecursiveTags rt
    join Posts p on p.Id = rt.PostId
    where p.OwnerUserId = tu.Id
    group by rt.Tag
    order by count(*) desc nulls last
    limit 1
) rt on true
where uw.MonthlyRank <= 50
union
select
    u.Id, u.DisplayName, u.Reputation, NULL, NULL, NULL, NULL, 0, 0, 0, 0, 0,NULL,
    'Other user'::text,
    0.0, NULL, NULL
from Users u
where u.Reputation between 5000 and 9999
order by Reputation desc
limit 100;