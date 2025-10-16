-- {"query": "1426.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1902} 
with RecursiveTagHierarchie as (
    select t.Id, t.TagName, array[t.Id] as Path from Tags t
    where t.WikiPostId is not null
    union all
    select t.Id, t.TagName, r.Path || t.Id from Tags t
    join RecursiveTagHierarchie r on r.Path[array_length(r.Path, 1)] <> t.Id -- just avoiding same sequential tag
), PostRankedVotes as (
    select
        p.Id,
        p.Title,
        p.PostTypeId,
        p.CreationDate,
        p.OwnerUserId,
        utReputation.RepTaggedUser,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        avg(case when v.VoteTypeId = 2 then 1.0 else 0 end) OVER (PARTITION BY p.PostTypeId ORDER BY p.Score ROWS BETWEEN 3 PRECEDING AND 3 FOLLOWING) as AvgSurroundingUpVotes,
        rank() over (partition by p.OwnerUserId order by p.Score desc) as RankByOwner,
        dict.DuplicateCount,
        MinLinkMinDate.MinLinkDate
    from Posts p
    left join Votes v on v.PostId = p.Id
    left join (
        select PostId, count(*) as DuplicateCount
        from PostLinks
        where LinkTypeId = 3
        group by PostId
    ) dict on dict.PostId = p.Id
    left join (
        select pl.PostId, min(pl.CreationDate) as MinLinkDate
        from PostLinks pl
        group by pl.PostId
    ) MinLinkMinDate on MinLinkMinDate.PostId = p.Id
    left join (
        select u.Id as UserId, sum(t.Count) as RepTaggedUser
        from Users u
        left join Posts p2 on p2.OwnerUserId = u.Id
        left join RecursiveTagHierarchie t on p2.Tags ilike concat('%', t.TagName ,'%')
        group by u.Id
    ) utReputation on utReputation.UserId = p.OwnerUserId
    group by p.Id, p.Title, p.PostTypeId, p.CreationDate, p.OwnerUserId, utReputation.RepTaggedUser, dict.DuplicateCount, MinLinkMinDate.MinLinkDate
), AvgCloseAndReopenTimes as (
    select
        ph.PostId,
        avg(case when ph.PostHistoryTypeId = 11 then extract(epoch from ph.CreationDate - t10.MinDate) else null end) as AvgReopenSeconds,
        t10.MinDate
    from PostHistory ph
    join (
        select PostId, min(CreationDate) as MinDate
        from PostHistory 
        where PostHistoryTypeId = 10 -- Post Closed
        group by PostId
    ) t10 on t10.PostId = ph.PostId
    where ph.PostHistoryTypeId = 11 -- Post Reopened
    group by ph.PostId, t10.MinDate
) 
select p.Id, p.Title, u.DisplayName as OwnerName, p.PostTypeId, p.CreationDate,
       case p.PostTypeId when 1 then 'Question' when 2 then 'Answer' else 'Other' end as PostTypeName,
       case when p.RankByOwner = 1 then 'Top post owner' else 'Other posts' end as OwnerRankCategory,
       coalesce(p.UpVotes, 0) as TotalUpVotes,
       coalesce(p.DownVotes, 0) as TotalDownVotes,
       coalesce(p.AvgSurroundingUpVotes,0) as Radius7VoteWindowAvg,
       p.DuplicateCount,
       coalesce(acrt.AvgReopenSeconds, 0)/3600.0 as AvgHoursToReopen,
       ac.MinDate as ClosedDate,
       case 
          when p.MinLinkDate is null then 'No links' 
          when p.MinLinkDate < p.CreationDate + interval '7 day' then 'Early linked' 
          else 'Late linked' 
       end AS LinkTimingCategory,
       coalesce(u.Reputation, 0) + coalesce(p.RepTaggedUser, 0) as ReputationPlusTaggedSum,
       LEFT(p.Title, 50) || CASE WHEN length(p.Title) > 50 THEN '...' ELSE '' END as SampleTitleTrunc
from PostRankedVotes p
left join Users u on u.Id = p.OwnerUserId
left join AvgCloseAndReopenTimes acrt on acrt.PostId = p.Id
left join (
  select PostId, min(CreationDate) as MinDate
  from PostHistory
  where PostHistoryTypeId=10
  group by PostId
) ac on ac.PostId = p.Id
where p.PostTypeId in (1,2)
  and (
    p.Title ilike '%fn%' or 
    p.Title ilike '%array%' or 
    (p.OwnerUserId is null and p.Title is null)
  )
order by p.RepTaggedUser desc nulls last, p.RankByOwner asc
limit 50

union

select p2.Id, p2.Title, u2.DisplayName as OwnerName, p2.PostTypeId, p2.CreationDate,
       case p2.PostTypeId when 1 then 'Question' when 2 then 'Answer' else 'Other' end as PostTypeName,
       'Unranked Set' as OwnerRankCategory,
       0 as TotalUpVotes,
       0 as TotalDownVotes,
       0 as Radius7VoteWindowAvg,
       0 as DuplicateCount,
       0 as AvgHoursToReopen,
       NULL as ClosedDate,
       'No link info' AS LinkTimingCategory,
       coalesce(u2.Reputation, 0) as ReputationPlusTaggedSum,
       LEFT(p2.Title, 50) || CASE WHEN length(p2.Title) > 50 THEN '...' ELSE '' END as SampleTitleTrunc
from Posts p2
left join Users u2 on u2.Id = p2.OwnerUserId
where p2.Score < 0
  and p2.PostTypeId = 1
  and (
      p2.Title like '%fail%' or
      p2.Tags like '%<sql>%'
  )
except
select Id, Title, OwnerName, PostTypeId, CreationDate, PostTypeName, OwnerRankCategory,
       TotalUpVotes, TotalDownVotes, Radius7VoteWindowAvg, DuplicateCount,
       AvgHoursToReopen, ClosedDate, LinkTimingCategory, ReputationPlusTaggedSum, SampleTitleTrunc
from (
    select p.Id, p.Title, u.DisplayName as OwnerName, p.PostTypeId, p.CreationDate,
           case p.PostTypeId when 1 then 'Question' when 2 then 'Answer' else 'Other' end as PostTypeName,
           case when p.RankByOwner = 1 then 'Top post owner' else 'Other posts' end as OwnerRankCategory,
           coalesce(p.UpVotes, 0) as TotalUpVotes,
           coalesce(p.DownVotes, 0) as TotalDownVotes,
           coalesce(p.AvgSurroundingUpVotes,0) as Radius7VoteWindowAvg,
           p.DuplicateCount,
           coalesce(acrt.AvgReopenSeconds, 0)/3600.0 as AvgHoursToReopen,
           ac.MinDate as ClosedDate,
           case 
              when p.MinLinkDate is null then 'No links' 
              when p.MinLinkDate < p.CreationDate + interval '7 day' then 'Early linked' 
              else 'Late linked' 
           end AS LinkTimingCategory,
           coalesce(u.Reputation, 0) + coalesce(p.RepTaggedUser, 0) as ReputationPlusTaggedSum,
           LEFT(p.Title, 50) || CASE WHEN length(p.Title) > 50 THEN '...' ELSE '' END as SampleTitleTrunc
    from PostRankedVotes p
    left join Users u on u.Id = p.OwnerUserId
    left join AvgCloseAndReopenTimes acrt on acrt.PostId = p.Id
    left join (
      select PostId, min(CreationDate) as MinDate
      from PostHistory
      where PostHistoryTypeId=10
      group by PostId
    ) ac on ac.PostId = p.Id
    where p.PostTypeId in (1,2)
      and (
        p.Title ilike '%fn%' or 
        p.Title ilike '%array%' or 
        (p.OwnerUserId is null and p.Title is null)
      )
    limit 50
) subquery
order by ReputationPlusTaggedSum desc nulls last, TotalUpVotes desc nulls last
limit 50;