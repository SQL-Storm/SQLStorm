with recursive recent_users as (
    select Id, DisplayName, Reputation, 
        coalesce(Location, 'Unknown') as Loc,
        CreationDate,
        row_number() over (order by Reputation desc, CreationDate) as rn
    from Users
    where CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '5' year
),
top_tags as (
    select t.Id, t.TagName,
        count(*) as total_posts,
        count(distinct p.OwnerUserId) as unique_owners,
        avg(coalesce(p.Score,0)) as avg_score
    from Tags t
    join Posts p on p.PostTypeId = 1 and p.Tags ilike '%' || '<' || t.TagName || '>' || '%'
    group by t.Id, t.TagName
    having count(*) > 50
    order by total_posts desc
    limit 20
),
question_details as (
    select p.Id as QuestionId, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount,
        amb_u.DisplayName as OwnerName,
        count(distinct a.Id) as AnswerCount,
        sum(coalesce(v.VoteCount,0)) as TotalVotes,
        coalesce(vm.VoteScore, 0) as MaxVoteScore
    from Posts p
    join Users amb_u on amb_u.Id = p.OwnerUserId
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    left join lateral (
        select VoteTypeId, count(*) as VoteCount
        from Votes
        where PostId = p.Id
        group by VoteTypeId
    ) v on true
    left join lateral (
        select sum(case when vt.Name in ('UpMod') then 1 when vt.Name in ('DownMod') then -1 else 0 end) as VoteScore
        from Votes v2
        join VoteTypes vt on vt.Id = v2.VoteTypeId
        where v2.PostId = p.Id
    ) vm on true
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, amb_u.DisplayName, vm.VoteScore
    having count(distinct a.Id) > 0
),
ranked_posts as (
    select qd.*,
        row_number() over (partition by qd.OwnerUserId order by qd.Score desc, qd.ViewCount desc) as UserPostRank
    from question_details qd
    where qd.Score > 0 and qd.ViewCount > 1000
),
close_counts as (
    select p.OwnerUserId, 
        sum(case when p.ClosedDate is not null then 1 else 0 end) as ClosedCount,
        count(*) as TotalQuestions,
        coalesce(sum(case when cht.PostHistoryTypeId = 10 and crt.Name is not null then 1 else 0 end),0) as KnownCloseReasons
    from Posts p
    left join PostHistory cht on cht.PostId = p.Id and cht.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id = cast(cht.Comment as integer)
    where p.PostTypeId = 1
    group by p.OwnerUserId
)

select ru.Id as UserId, ru.DisplayName, ru.Reputation, ru.Loc,
    t.TagName,
    tp.QuestionId, tp.Title, tp.CreationDate as QuestionCreated,
    tp.Score as QuestionScore, tp.ViewCount,
    tp.AnswerCount, tp.TotalVotes, tp.MaxVoteScore,
    cc.ClosedCount, cc.TotalQuestions, cc.KnownCloseReasons,
    (select count(*) from Badges b where b.UserId = ru.Id and b.Class = 1) as GoldBadges,
    (select count(*) from Badges b where b.UserId = ru.Id and b.Class = 2) as SilverBadges,
    (select count(*) from Badges b where b.UserId = ru.Id and b.Class = 3) as BronzeBadges,
    CASE
      WHEN tp.Title IS NOT NULL THEN tp.Title
      ELSE '[Untitled]'
    END
    || ' [Score: ' || cast(tp.Score as varchar) || ', Views: ' || cast(tp.ViewCount as varchar) || ']' as SummaryText,
    case 
        when cc.TotalQuestions > 0 then round(100.0 * cast(cc.ClosedCount as numeric) / cc.TotalQuestions,2)
        else null
    end as PercentClosed
from recent_users ru
left join Posts p on p.OwnerUserId = ru.Id and p.PostTypeId = 1
left join top_tags t on p.Tags ilike '%' || '<' || t.TagName || '>' || '%'
left join ranked_posts tp on tp.OwnerUserId = ru.Id and tp.UserPostRank = 1
left join close_counts cc on cc.OwnerUserId = ru.Id
where ru.rn <= 100 and tp.Score is not null and coalesce(t.TagName, '') != ''

union all

select ru.Id as UserId, ru.DisplayName, ru.Reputation, ru.Loc,
    'General' as TagName,
    null as QuestionId, null as Title, null as QuestionCreated,
    null as QuestionScore, null as ViewCount,
    null as AnswerCount, null as TotalVotes, null as MaxVoteScore,
    0 as ClosedCount, 0 as TotalQuestions, 0 as KnownCloseReasons,
    0 as GoldBadges,
    0 as SilverBadges,
    0 as BronzeBadges,
    null as SummaryText,
    null as PercentClosed
from recent_users ru
where not exists (
    select 1 from Posts p where p.OwnerUserId = ru.Id and p.PostTypeId = 1
)
order by Reputation desc, UserId
limit 200;