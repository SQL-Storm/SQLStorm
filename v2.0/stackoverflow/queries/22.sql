-- {"query": "22.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2936}
with recent_questions as (
    select
        p.Id as QuestionId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        coalesce(p.AnswerCount, 0) as AnswerCount
    from Posts p
    where p.PostTypeId = 1
      and p.CreationDate >= (select max(CreationDate) - interval '180 days' from Posts where PostTypeId = 1)
),
answers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswerOwnerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc, a.Id asc) as rn_score_desc,
        row_number() over (partition by a.ParentId order by a.CreationDate asc, a.Id asc) as rn_first
    from Posts a
    where a.PostTypeId = 2
),
best_answers as (
    select
        q.QuestionId,
        a.AnswerId as BestAnswerId,
        a.AnswerOwnerId,
        a.AnswerScore,
        a.AnswerCreationDate
    from recent_questions q
    join answers a
      on a.QuestionId = q.QuestionId
     and a.rn_score_desc = 1
),
first_answers as (
    select
        q.QuestionId,
        a.AnswerId as FirstAnswerId,
        a.AnswerOwnerId as FirstAnswerOwnerId,
        a.AnswerCreationDate as FirstAnswerCreationDate
    from recent_questions q
    join answers a
      on a.QuestionId = q.QuestionId
     and a.rn_first = 1
),
question_votes as (
    select
        v.PostId as QuestionId,
        sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end) as NetVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
        count(*) as TotalVotes,
        max(v.CreationDate) as LastVoteDate
    from Votes v
    join recent_questions q on q.QuestionId = v.PostId
    group by v.PostId
),
answer_updown as (
    select
        v.PostId as AnswerId,
        sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end) as AnswerNetVotes
    from Votes v
    join Posts p on p.Id = v.PostId and p.PostTypeId = 2
    group by v.PostId
),
tag_expansion as (
    select
        q.QuestionId,
        -- portable splitting of tags: remove leading and trailing <> and split on '><'
        -- use replace + regexp to normalize then split; string_to_array and unnest are PostgreSQL-specific but many DBs support similar. Keep string_to_array/unnest for DBs that support them; if not, adjust downstream.
        unnest(string_to_array(substring(coalesce(q.Tags, ''), 2, greatest(length(coalesce(q.Tags, '')) - 2, 0)), '><')) as Tag
    from recent_questions q
),
top_tags as (
    select
        Tag,
        count(*) as TagCount,
        row_number() over (order by count(*) desc, Tag asc) as rn
    from tag_expansion
    group by Tag
),
user_activity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        date_trunc('day', u.CreationDate) as UserSinceDay,
        u.Location,
        u.UpVotes,
        u.DownVotes,
        u.Views
    from Users u
),
question_edits as (
    select
        ph.PostId as QuestionId,
        sum(case when ph.PostHistoryTypeId in (4,5,6,7,8,9,24) then 1 else 0 end) as EditCount,
        max(ph.CreationDate) as LastEditDate,
        max(case when ph.PostHistoryTypeId = 50 then 1 else 0 end) = 1 as WasCommunityBump,
        sum(case when ph.PostHistoryTypeId in (10,11,12,13,14,15,19,20,35) then 1 else 0 end) as ModEvents
    from PostHistory ph
    join recent_questions q on q.QuestionId = ph.PostId
    group by ph.PostId
),
dup_links as (
    select
        pl.PostId as DuplicateOfQuestionId,
        sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as DuplicateLinks,
        sum(case when pl.LinkTypeId = 1 then 1 else 0 end) as GenericLinks
    from PostLinks pl
    join recent_questions q on q.QuestionId = pl.PostId
    group by pl.PostId
),
closed_reasons as (
    select
        ph.PostId as QuestionId,
        min(ph.CreationDate) as FirstClosedDate,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate else null end) as LastReopenedDate,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate else null end) as LastClosedDate,
        max(
            case
                when regexp_replace(coalesce(ph.Comment, ''), '[^0-9]', '', 'g') = '' then null
                else cast(regexp_replace(coalesce(ph.Comment, ''), '[^0-9]', '', 'g') as integer)
            end
        ) as LastCloseReasonId
    from PostHistory ph
    where ph.PostHistoryTypeId in (10,11)
    group by ph.PostId
),
accepted_status as (
    select
        q.QuestionId,
        case when p.AcceptedAnswerId is not null then 1 else 0 end as HasAccepted,
        p.AcceptedAnswerId
    from recent_questions q
    join Posts p on p.Id = q.QuestionId
),
badge_summary as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldCount,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverCount,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeCount,
        count(*) as TotalBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
ranked_questions as (
    select
        q.QuestionId,
        q.OwnerUserId,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.CreationDate,
        q.Title,
        coalesce(qv.NetVotes, 0) as NetVotes,
        coalesce(qv.Favorites, 0) as Favorites,
        coalesce(qe.EditCount, 0) as EditCount,
        coalesce(d.DuplicateLinks, 0) as DuplicateLinks,
        coalesce(d.GenericLinks, 0) as GenericLinks,
        coalesce(cr.LastCloseReasonId, 0) as LastCloseReasonId,
        cr.FirstClosedDate as FirstClosedDate,
        cr.LastReopenedDate as LastReopenedDate,
        coalesce(ab.AnswerNetVotes, 0) as BestAnswerNetVotes,
        coalesce(ba.AnswerScore, 0) as BestAnswerScore,
        case when ac.HasAccepted = 1 then 1 else 0 end as HasAccepted
    from recent_questions q
    left join question_votes qv on qv.QuestionId = q.QuestionId
    left join question_edits qe on qe.QuestionId = q.QuestionId
    left join dup_links d on d.DuplicateOfQuestionId = q.QuestionId
    left join accepted_status ac on ac.QuestionId = q.QuestionId
    left join best_answers ba on ba.QuestionId = q.QuestionId
    left join answer_updown ab on ab.AnswerId = ba.BestAnswerId
    left join closed_reasons cr on cr.QuestionId = q.QuestionId
),
scored as (
    select
        rq.QuestionId,
        rq.OwnerUserId,
        rq.Score,
        rq.ViewCount,
        rq.AnswerCount,
        rq.CreationDate,
        rq.Title,
        rq.NetVotes,
        rq.Favorites,
        rq.EditCount,
        rq.DuplicateLinks,
        rq.GenericLinks,
        rq.LastCloseReasonId,
        rq.FirstClosedDate,
        rq.LastReopenedDate,
        rq.BestAnswerNetVotes,
        rq.BestAnswerScore,
        rq.HasAccepted,
        greatest(0,
            0.40 * coalesce(rq.NetVotes, 0) +
            0.25 * coalesce(rq.ViewCount, 0) / nullif(ln(1 + rq.ViewCount), 0) +
            0.20 * coalesce(rq.BestAnswerNetVotes, 0) +
            0.10 * coalesce(rq.EditCount, 0) -
            0.30 * case when rq.LastCloseReasonId in (101,1) then 1 else 0 end -
            0.15 * coalesce(rq.DuplicateLinks, 0) +
            0.10 * case when rq.HasAccepted = 1 then 1 else 0 end
        ) as PerfScore
    from ranked_questions rq
),
owner_stats as (
    select
        q.OwnerUserId as UserId,
        count(*) as OwnerQuestionCount,
        avg(q.Score) as AvgQuestionScore,
        percentile_cont(0.5) within group (order by q.ViewCount) as MedianQuestionViews,
        sum(case when q.HasAccepted = 1 then 1 else 0 end) as AcceptedQuestions
    from scored q
    group by q.OwnerUserId
),
owner_baseline as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.Location,
        ua.UpVotes,
        ua.DownVotes,
        ua.Views as ProfileViews,
        coalesce(bs.TotalBadges, 0) as TotalBadges,
        coalesce(bs.GoldCount, 0) as GoldBadges,
        coalesce(bs.SilverCount, 0) as SilverBadges,
        coalesce(bs.BronzeCount, 0) as BronzeBadges,
        bs.LastBadgeDate as LastBadgeDate
    from user_activity ua
    left join badge_summary bs on bs.UserId = ua.UserId
),
tag_rollup as (
    select
        te.QuestionId,
        string_agg(te.Tag, ',' order by te.Tag) as TagList,
        sum(case when te.Tag in (select Tag from top_tags where rn <= 25) then 1 else 0 end) as TopTagHits
    from tag_expansion te
    group by te.QuestionId
),
question_string_ops as (
    select
        q.QuestionId,
        lower(coalesce(q.Title, '')) as title_lower,
        char_length(coalesce(q.Title, '')) as title_len,
        position('how' in lower(coalesce(q.Title, ''))) as pos_how,
        regexp_replace(coalesce(q.Title, ''), '\s+', ' ', 'g') as title_compact
    from recent_questions q
),
final_rank as (
    select
        s.QuestionId,
        s.OwnerUserId,
        s.Score,
        s.ViewCount,
        s.AnswerCount,
        s.PerfScore,
        s.HasAccepted,
        coalesce(tr.TagList, '') as TagList,
        coalesce(tr.TopTagHits, 0) as TopTagHits,
        qs.title_lower,
        qs.title_len,
        qs.pos_how,
        qs.title_compact,
        row_number() over (
            partition by (case when s.HasAccepted = 1 then 'accepted' else 'unaccepted' end)
            order by s.PerfScore desc, s.NetVotes desc, s.ViewCount desc, s.QuestionId asc
        ) as rn_class_rank,
        dense_rank() over (order by s.PerfScore desc) as overall_dense_rank
    from scored s
    left join tag_rollup tr on tr.QuestionId = s.QuestionId
    left join question_string_ops qs on qs.QuestionId = s.QuestionId
)
select
    fr.QuestionId,
    fr.OwnerUserId,
    u.DisplayName as OwnerDisplayName,
    u.Reputation,
    coalesce(ob.TotalBadges, 0) as OwnerTotalBadges,
    coalesce(os.OwnerQuestionCount, 0) as OwnerQuestionCount,
    coalesce(round(os.AvgQuestionScore, 2), 0) as OwnerAvgQuestionScore,
    coalesce(os.MedianQuestionViews, 0) as OwnerMedianQuestionViews,
    fr.Score as QuestionScore,
    fr.ViewCount,
    fr.AnswerCount,
    fr.HasAccepted,
    fr.PerfScore,
    fr.TagList,
    fr.TopTagHits,
    fr.title_len,
    fr.pos_how,
    ba.BestAnswerId,
    ba.AnswerOwnerId as BestAnswerOwnerId,
    fa.FirstAnswerId,
    fa.FirstAnswerOwnerId,
    case
        when fr.TopTagHits >= 3 and fr.PerfScore > (select avg(PerfScore) from scored) then 'HOT'
        when fr.PerfScore >= (select percentile_cont(0.9) within group (order by PerfScore) from scored) then 'TOP10'
        when fr.PerfScore <= (select percentile_cont(0.1) within group (order by PerfScore) from scored) then 'BOTTOM10'
        else 'NORMAL'
    end as PerfBucket,
    fr.rn_class_rank,
    fr.overall_dense_rank
from final_rank fr
left join best_answers ba on ba.QuestionId = fr.QuestionId
left join first_answers fa on fa.QuestionId = fr.QuestionId
left join owner_stats os on os.UserId = fr.OwnerUserId
left join owner_baseline ob on ob.UserId = fr.OwnerUserId
left join Users u on u.Id = fr.OwnerUserId
where (
    fr.PerfScore > 0
    or fr.HasAccepted = 1
    or fr.TopTagHits >= 2
)
and (
    fr.title_len > 10
    and (fr.pos_how = 1 or fr.pos_how = 0 or fr.pos_how is null)
)
order by fr.PerfScore desc nulls last, fr.ViewCount desc, fr.QuestionId asc
limit 250;