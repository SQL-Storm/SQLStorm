-- {"query": "8080.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2837} 
with recent_questions as (
    select
        p.Id as QuestionId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        coalesce(p.AnswerCount, 0) as AnswerCount
    from Posts p
    where p.PostTypeId = 1
      and p.CreationDate >= (select date_trunc('month', max(CreationDate)) - interval '6 months' from Posts where PostTypeId = 1)
),
answers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswerUserId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate
    from Posts a
    where a.PostTypeId = 2
),
question_activity as (
    select
        q.QuestionId,
        count(distinct c.Id) filter (where c.Id is not null) as CommentCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as FavoriteVotes,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6,24)) as LastEditDate
    from recent_questions q
    left join Comments c on c.PostId = q.QuestionId
    left join Votes v on v.PostId = q.QuestionId
    left join PostHistory ph on ph.PostId = q.QuestionId
    group by q.QuestionId
),
first_answer as (
    select distinct on (a.QuestionId)
        a.QuestionId,
        a.AnswerId,
        a.AnswerUserId,
        a.AnswerScore,
        a.AnswerCreationDate
    from answers a
    join recent_questions q on q.QuestionId = a.QuestionId
    order by a.QuestionId, a.AnswerCreationDate asc, a.AnswerId asc
),
accepted_answer as (
    select
        q.QuestionId,
        p.Id as AcceptedAnswerId,
        p.OwnerUserId as AcceptedOwnerId,
        p.Score as AcceptedScore,
        p.CreationDate as AcceptedCreationDate
    from recent_questions q
    join Posts pq on pq.Id = q.QuestionId
    join Posts p on p.Id = pq.AcceptedAnswerId
),
tag_expanded as (
    select
        q.QuestionId,
        unnest(string_to_array(substring(coalesce(q.Tags, ''), 2, greatest(length(coalesce(q.Tags,'')) - 2, 0)), '><')) as tag
    from recent_questions q
),
tag_rank as (
    select
        t.QuestionId,
        t.tag,
        row_number() over (partition by t.QuestionId order by coalesce((select Count from Tags where TagName = t.tag), 0) desc, t.tag) as tag_pop_rank
    from tag_expanded t
),
top3_tags as (
    select tr.QuestionId, string_agg(tr.tag, ', ' order by tr.tag_pop_rank) as TopTags
    from tag_rank tr
    where tr.tag_pop_rank <= 3
    group by tr.QuestionId
),
user_stats as (
    select
        u.Id as UserId,
        u.Reputation,
        u.CreationDate as UserCreationDate,
        u.DisplayName,
        u.UpVotes,
        u.DownVotes,
        u.Views,
        coalesce((
            select count(*) from Badges b where b.UserId = u.Id and b.Class = 1
        ),0) as GoldBadges,
        coalesce((
            select count(*) from Badges b where b.UserId = u.Id and b.Class = 2
        ),0) as SilverBadges,
        coalesce((
            select count(*) from Badges b where b.UserId = u.Id and b.Class = 3
        ),0) as BronzeBadges
    from Users u
),
dup_links as (
    select
        pl.PostId as QuestionId,
        count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinks,
        count(*) filter (where pl.LinkTypeId = 1) as RelatedLinks
    from PostLinks pl
    group by pl.PostId
),
closing_info as (
    select
        ph.PostId as QuestionId,
        min(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as FirstClosedDate,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 11) as LastReopenDate,
        max(case when ph.PostHistoryTypeId = 10 then try_cast(ph.Comment as int) end) as LastCloseReasonId
    from PostHistory ph
    group by ph.PostId
),
vote_time_series as (
    select
        v.PostId as QuestionId,
        date_trunc('day', v.CreationDate) as VoteDay,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesDay,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesDay
    from Votes v
    join recent_questions q on q.QuestionId = v.PostId
    group by v.PostId, date_trunc('day', v.CreationDate)
),
vote_peaks as (
    select
        QuestionId,
        max(UpVotesDay) as PeakDailyUpVotes,
        max(DownVotesDay) as PeakDailyDownVotes
    from vote_time_series
    group by QuestionId
),
answerer_user_stats as (
    select
        fa.QuestionId,
        us.DisplayName as FirstAnswerer,
        us.Reputation as FirstAnswererRep,
        us.GoldBadges as FirstAnswererGold,
        us.SilverBadges as FirstAnswererSilver,
        us.BronzeBadges as FirstAnswererBronze
    from first_answer fa
    left join user_stats us on us.UserId = fa.AnswerUserId
),
asker_user_stats as (
    select
        q.QuestionId,
        us.DisplayName as Asker,
        us.Reputation as AskerRep,
        us.GoldBadges as AskerGold,
        us.SilverBadges as AskerSilver,
        us.BronzeBadges as AskerBronze
    from recent_questions q
    left join user_stats us on us.UserId = q.OwnerUserId
),
normalized as (
    select
        q.QuestionId,
        q.Title,
        coalesce(tt.TopTags, '') as TopTags,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        qa.CommentCount,
        qa.UpVotes,
        qa.DownVotes,
        qa.FavoriteVotes,
        qa.LastEditDate,
        dl.DuplicateLinks,
        dl.RelatedLinks,
        ci.FirstClosedDate,
        ci.LastReopenDate,
        ci.LastCloseReasonId,
        fa.AnswerId as FirstAnswerId,
        fa.AnswerScore as FirstAnswerScore,
        fa.AnswerCreationDate as FirstAnswerDate,
        aa.AcceptedAnswerId,
        aa.AcceptedScore,
        aa.AcceptedCreationDate,
        au.FirstAnswerer,
        au.FirstAnswererRep,
        au.FirstAnswererGold,
        au.FirstAnswererSilver,
        au.FirstAnswererBronze,
        su.Asker,
        su.AskerRep,
        su.AskerGold,
        su.AskerSilver,
        su.AskerBronze,
        vp.PeakDailyUpVotes,
        vp.PeakDailyDownVotes
    from recent_questions q
    left join question_activity qa on qa.QuestionId = q.QuestionId
    left join dup_links dl on dl.QuestionId = q.QuestionId
    left join closing_info ci on ci.QuestionId = q.QuestionId
    left join first_answer fa on fa.QuestionId = q.QuestionId
    left join accepted_answer aa on aa.QuestionId = q.QuestionId
    left join top3_tags tt on tt.QuestionId = q.QuestionId
    left join answerer_user_stats au on au.QuestionId = q.QuestionId
    left join asker_user_stats su on su.QuestionId = q.QuestionId
    left join vote_peaks vp on vp.QuestionId = q.QuestionId
),
calc as (
    select
        n.*,
        case
            when n.ViewCount is null or n.ViewCount = 0 then null
            else round((n.UpVotes - n.DownVotes)::numeric / nullif(n.ViewCount, 0), 6)
        end as VoteViewRatio,
        case
            when n.AnswerId is not null then extract(epoch from (n.AnswerCreationDate - n.CreationDate)) / 3600.0
            else null
        end as HoursToFirstAnswer,
        case
            when n.AcceptedAnswerId is not null then extract(epoch from (n.AcceptedCreationDate - n.CreationDate)) / 3600.0
            else null
        end as HoursToAccepted,
        case
            when n.FirstClosedDate is not null then extract(epoch from (n.FirstClosedDate - n.CreationDate)) / 3600.0
            else null
        end as HoursToClose,
        case
            when n.LastEditDate is not null then extract(epoch from (n.LastEditDate - n.CreationDate)) / 3600.0
            else null
        end as HoursToLastEdit,
        case when n.Score is null then 0 else n.Score end
        + coalesce(n.UpVotes,0) * 2
        - coalesce(n.DownVotes,0) * 2
        + coalesce(n.FavoriteVotes,0)
        + coalesce(n.PeakDailyUpVotes,0)
        - coalesce(n.PeakDailyDownVotes,0)
        + coalesce(n.FirstAnswerScore,0)
        + coalesce(n.AcceptedScore,0) * 3
        + coalesce(10 - least(greatest(coalesce(n.AnswerCount,0),0),10), 0)
        as HeuristicHotness
    from normalized n
),
ranked as (
    select
        c.*,
        dense_rank() over (order by c.HeuristicHotness desc nulls last, c.ViewCount desc nulls last, c.Score desc nulls last, c.CreationDate desc) as HotnessRank,
        row_number() over (order by c.CreationDate desc, c.QuestionId) as RecencyRank,
        percent_rank() over (order by c.VoteViewRatio desc nulls last) as VoteViewPct
    from calc c
),
closed_reason_text as (
    select
        r.QuestionId,
        crt.Name as CloseReasonName
    from (
        select QuestionId, LastCloseReasonId
        from normalized
        where LastCloseReasonId is not null
    ) r
    left join CloseReasonTypes crt on crt.Id = r.LastCloseReasonId
),
final as (
    select
        r.QuestionId,
        r.Title,
        r.TopTags,
        r.CreationDate,
        r.Score,
        r.ViewCount,
        r.CommentCount,
        r.UpVotes,
        r.DownVotes,
        r.FavoriteVotes,
        r.LastEditDate,
        r.DuplicateLinks,
        r.RelatedLinks,
        r.FirstClosedDate,
        r.LastReopenDate,
        coalesce(crt.CloseReasonName, 'Unknown') as CloseReasonName,
        r.FirstAnswerId,
        r.FirstAnswerScore,
        r.FirstAnswerDate,
        r.AcceptedAnswerId,
        r.AcceptedScore,
        r.AcceptedCreationDate,
        r.FirstAnswerer,
        r.FirstAnswererRep,
        r.FirstAnswererGold,
        r.FirstAnswererSilver,
        r.FirstAnswererBronze,
        r.Asker,
        r.AskerRep,
        r.AskerGold,
        r.AskerSilver,
        r.AskerBronze,
        r.PeakDailyUpVotes,
        r.PeakDailyDownVotes,
        r.VoteViewRatio,
        r.HoursToFirstAnswer,
        r.HoursToAccepted,
        r.HoursToClose,
        r.HoursToLastEdit,
        r.HeuristicHotness,
        r.HotnessRank,
        r.RecencyRank,
        r.VoteViewPct
    from ranked r
    left join closed_reason_text crt on crt.QuestionId = r.QuestionId
)
select *
from final
where
    coalesce(TopTags, '') not like '%[meta]%'
    and (
        AcceptedAnswerId is not null
        or (FirstAnswerId is not null and HoursToFirstAnswer <= 48)
        or HeuristicHotness > (
            select percentile_disc(0.75) within group (order by HeuristicHotness)
            from ranked
        )
    )
    and (
        ViewCount > 0
        and coalesce(UpVotes,0) + coalesce(DownVotes,0) > 0
        and (VoteViewRatio is null or VoteViewRatio >= 0)
    )
order by
    HotnessRank asc,
    RecencyRank asc
limit 250;