with recursive RecursiveCTE as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        1 as Depth,
        cast(p.Id as varchar) as Path
    from Posts p
    where p.PostTypeId = 1
      and p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '2 years'
    
    union all

    select
        child.Id as PostId,
        child.PostTypeId,
        child.OwnerUserId,
        child.CreationDate,
        child.Score,
        child.ViewCount,
        parent.Depth + 1,
        parent.Path || '->' || cast(child.Id as varchar)
    from Posts child
    join RecursiveCTE parent on child.ParentId = parent.PostId
    where parent.Depth < 3
)
, AnswersWithRank as (
    select
        r.PostId,
        r.PostTypeId,
        r.OwnerUserId,
        r.CreationDate,
        r.Score,
        r.ViewCount,
        r.Depth,
        r.Path,
        count(case when vt.Name = 'UpMod' then v.Id end) as UpVotesCount,
        count(case when vt.Name = 'DownMod' then v.Id end) as DownVotesCount,
        avg(case when length(trim(coalesce(c.Text, ''))) > 0 then length(trim(c.Text)) else null end) as AvgCommentLength,
        rank() over (partition by r.Path order by r.Score desc, r.ViewCount desc) as ScoreRank
    from RecursiveCTE r
    left join Votes v on v.PostId = r.PostId
    left join VoteTypes vt on vt.Id = v.VoteTypeId
    left join Comments c on c.PostId = r.PostId
    group by
        r.PostId, r.PostTypeId, r.OwnerUserId, r.CreationDate, r.Score, r.ViewCount, r.Depth, r.Path
)

, WindowExperience as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionsCount,
        count(distinct ans.Id) as AnswersCount,
        row_number() over (order by u.Reputation desc, u.CreationDate) as RankByReputation,
        percentile_cont(0.5) within group (order by coalesce(ans.Score,0)) as MedianAnswerScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    left join Posts ans on ans.OwnerUserId = u.Id and ans.PostTypeId = 2
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
)

select distinct
    a.PostId,
    a.PostTypeId,
    a.OwnerUserId,
    coalesce(u.DisplayName, a.OwnerUserId::text) as OwnerName,
    a.CreationDate,
    a.Score,
    a.UpVotesCount,
    a.DownVotesCount,
    a.ViewCount,
    case when a.Depth = 1 then 'Question'
         when a.Depth = 2 then 'Answer to Question'
         else 'Follow-up Answer'
         end as PostDepthLabel,
    w.RankByReputation,
    coalesce(ph_latest.UserDisplayName, ph.UserDisplayName, u.DisplayName) as LastEditorName,
    case
        when ph.PostHistoryTypeId in (10,11) then ph.Comment
        when ph.PostHistoryTypeId = 14 then 'Locked'
        when ph.PostHistoryTypeId = 15 then 'Unlocked'
        else 'Open/Not applicable'
    end as PostStatusDesc,
    freq.TagName,
    freq.NumberOfPostsWithTag,
    (
            select count(distinct ph2.Id)
            from PostHistory ph2
            join CloseReasonTypes cr on cr.Id = cast(ph2.Comment as integer)
            where ph2.PostId = a.PostId
              and ph2.PostHistoryTypeId = 10
              and cr.Name like '%Duplicate%'
    ) as DuplicateCloseVotesCount
from
    AnswersWithRank a
left join Users u on u.Id = a.OwnerUserId
left join Posts p_question on p_question.Id = (
    select p2.Id from Posts p2 where p2.AcceptedAnswerId = a.PostId limit 1
)
left join lateral (
    select ph.*
    from PostHistory ph
    where ph.PostId = a.PostId
    order by ph.CreationDate desc nulls last
    limit 1
) ph on true
left join lateral (
    select ph_latest.*
    from PostHistory ph_latest
    where ph_latest.PostId = a.PostId
      and ph_latest.UserId is not null
    order by ph_latest.CreationDate desc nulls last
    limit 1
) ph_latest on true
left join (
    select
        unnest(string_to_array(trim(both '<>' from Tags), '> <')) as TagName,
        count(*) as NumberOfPostsWithTag
    from Posts
    where Tags is not null and length(trim(Tags)) > 0
    group by TagName
    order by NumberOfPostsWithTag desc
    limit 10
) freq on freq.TagName is not null and a.PostTypeId = 1 and a.PostId in (
    select Id from Posts ptag where ptag.Tags like '%' || freq.TagName || '%'
)
left join WindowExperience w on w.UserId = a.OwnerUserId
where a.ScoreRank = 1
  and a.Depth <= 2
  and (a.ViewCount > 50 or a.Score > 0)
  and (
      cast(a.PostId as text) ilike '%7%'
      or coalesce(u.Location, '') ilike '%USA%'
      or exists (
          select 1
          from Posts pcheck
          where pcheck.Id = a.PostId
            and pcheck.Tags like '%<sql>%'
      )
  )
order by w.RankByReputation, a.Score desc, a.ViewCount desc
limit 100;