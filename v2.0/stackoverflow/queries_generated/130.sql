-- {"query": "130.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3899} 
with params as (
    select 
        now() - interval '365 days' as from_date,
        50 as min_score,
        5 as min_ans,
        100 as min_rep
),
-- 1) Active questions in last year with various derived metrics
recent_questions as (
    select
        p.Id as QuestionId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        coalesce(p.LastActivityDate, p.CreationDate) as LastActivityDate
    from Posts p
    join PostTypes pt on pt.Id = p.PostTypeId and pt.Name = 'Question'
    cross join params par
    where p.CreationDate >= par.from_date
      and p.Score >= par.min_score
      and coalesce(p.AnswerCount, 0) >= par.min_ans
),
-- 2) Answers for those questions
answers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswerOwnerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate
    from Posts a
    join PostTypes pt on pt.Id = a.PostTypeId and pt.Name = 'Answer'
    where exists (
        select 1
        from recent_questions q
        where q.QuestionId = a.ParentId
    )
),
-- 3) Aggregate per question over answers
answer_agg as (
    select
        a.QuestionId,
        count(*) as AnswerCnt,
        sum(case when a.AnswerScore > 0 then 1 else 0 end) as PosAnswerCnt,
        max(a.AnswerScore) as MaxAnswerScore,
        min(a.AnswerScore) as MinAnswerScore,
        avg(a.AnswerScore::numeric) as AvgAnswerScore,
        count(distinct a.AnswerOwnerId) as DistinctAnswerers,
        max(a.AnswerCreationDate) as LastAnswerDate
    from answers a
    group by a.QuestionId
),
-- 4) Votes on questions and answers (windowed stats)
qa_votes as (
    select
        v.PostId,
        v.VoteTypeId,
        v.CreationDate::date as VoteDate,
        count(*) as VoteCnt
    from Votes v
    join params par on true
    where v.CreationDate >= par.from_date
      and v.VoteTypeId in (2,3,8,9,10,11,12) -- up, down, bounties, deletion, undeletion, spam
    group by v.PostId, v.VoteTypeId, v.CreationDate::date
),
qa_votes_rollup as (
    select
        p.Id as PostId,
        sum(case when v.VoteTypeId = 2 then v.VoteCnt else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then v.VoteCnt else 0 end) as DownVotes,
        sum(case when v.VoteTypeId in (8,9) then v.VoteCnt else 0 end) as BountyEvents,
        sum(case when v.VoteTypeId in (10,11,12) then v.VoteCnt else 0 end) as ModEvents
    from Posts p
    left join qa_votes v on v.PostId = p.Id
    where exists (select 1 from recent_questions q where q.QuestionId = p.Id)
       or exists (select 1 from answers a where a.AnswerId = p.Id)
    group by p.Id
),
-- 5) Denormalized tag array for recent questions
q_tags as (
    select
        q.QuestionId,
        string_to_array(substring(coalesce(q.Tags, ''), 2, greatest(length(coalesce(q.Tags,'')) - 2, 0)), '><') as tag_arr
    from recent_questions q
),
-- 6) Tag statistics across recent questions (distinct questions per tag)
tag_stats as (
    select
        unnest(tag_arr) as tag_name,
        count(distinct QuestionId) as q_per_tag
    from q_tags
    group by unnest(tag_arr)
),
-- 7) Link relationships (duplicates and linked)
q_links as (
    select
        pl.PostId as SrcId,
        pl.RelatedPostId as DstId,
        lt.Name as LinkType,
        min(pl.CreationDate) as FirstLinkDate,
        count(*) as LinkCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where pl.PostId in (select QuestionId from recent_questions)
       or pl.RelatedPostId in (select QuestionId from recent_questions)
    group by pl.PostId, pl.RelatedPostId, lt.Name
),
-- 8) Post history events of interest (close/reopen/migrate/notice)
q_history as (
    select
        ph.PostId,
        ph.PostHistoryTypeId,
        min(ph.CreationDate) as FirstEvent,
        max(ph.CreationDate) as LastEvent,
        count(*) as EventCnt,
        -- extract possible close reason id embedded in Comment column when closed
        max(case when ph.PostHistoryTypeId = 10 then nullif(trim(ph.Comment), '') end) as CloseReasonRaw
    from PostHistory ph
    where ph.PostId in (select QuestionId from recent_questions)
      and ph.PostHistoryTypeId in (10,11,35,36,33,34,50,52,53)
    group by ph.PostId, ph.PostHistoryTypeId
),
-- 9) Users baseline and activity
user_base as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(nullif(trim(u.Location),''), 'Unknown') as Location,
        u.Views,
        u.UpVotes,
        u.DownVotes
    from Users u
),
user_badge_agg as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBadges
    from Badges b
    group by b.UserId
),
-- 10) Compute question-level quality and activity scores
question_metrics as (
    select
        q.QuestionId,
        q.OwnerUserId,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.Title,
        q.Tags,
        q.AcceptedAnswerId,
        q.AnswerCount,
        q.CommentCount,
        q.FavoriteCount,
        aa.AnswerCnt,
        aa.PosAnswerCnt,
        aa.MaxAnswerScore,
        aa.MinAnswerScore,
        aa.AvgAnswerScore,
        aa.DistinctAnswerers,
        aa.LastAnswerDate,
        qv_up.UpVotes as QUp,
        qv_up.DownVotes as QDown,
        coalesce(qv_ans.UpVotes,0) as AnsUp,
        coalesce(qv_ans.DownVotes,0) as AnsDown,
        (coalesce(qv_up.UpVotes,0) - coalesce(qv_up.DownVotes,0) + coalesce(qv_ans.UpVotes,0) - coalesce(qv_ans.DownVotes,0)) as NetVotesAll,
        -- heuristic quality score
        (q.Score * 2
         + coalesce(aa.PosAnswerCnt,0)
         + least(coalesce(q.ViewCount,0) / 1000, 100)
         + coalesce(q.FavoriteCount,0)
         + case when q.AcceptedAnswerId is not null then 5 else 0 end
        ) as QualityScore
    from recent_questions q
    left join answer_agg aa on aa.QuestionId = q.QuestionId
    left join qa_votes_rollup qv_up on qv_up.PostId = q.QuestionId
    left join (
        select
            a.QuestionId,
            sum(coalesce(v.UpVotes,0)) as UpVotes,
            sum(coalesce(v.DownVotes,0)) as DownVotes
        from answers a
        left join qa_votes_rollup v on v.PostId = a.AnswerId
        group by a.QuestionId
    ) qv_ans on qv_ans.QuestionId = q.QuestionId
),
-- 11) Rank questions by multiple windows
question_ranks as (
    select
        qm.*,
        rank() over (order by QualityScore desc, NetVotesAll desc, coalesce(ViewCount,0) desc) as RankOverall,
        dense_rank() over (order by coalesce(AnswerCnt,0) desc) as RankByAnswers,
        row_number() over (order by coalesce(ViewCount,0) desc, Score desc) as RankByViews,
        percent_rank() over (order by coalesce(ViewCount,0)) as ViewPercentile,
        ntile(10) over (order by QualityScore desc) as QualityDecile
    from question_metrics qm
),
-- 12) Extract top tag per question by global tag popularity within recent set
question_top_tag as (
    select
        qt.QuestionId,
        (select t.tag_name
         from (
            select unnest(qt.tag_arr) as tag_name
         ) s
         join tag_stats ts on ts.tag_name = s.tag_name
         order by ts.q_per_tag desc, s.tag_name asc
         limit 1
        ) as TopTag
    from q_tags qt
),
-- 13) Close reason extraction (json text or numeric in Comment)
question_close_reason as (
    select
        qh.PostId as QuestionId,
        -- attempt to parse numeric codes; fallback to raw
        case
            when qh.CloseReasonRaw ~ '^[0-9]+$' then qh.CloseReasonRaw
            when qh.CloseReasonRaw is null then null
            else null
        end::int as CloseReasonId
    from q_history qh
    where qh.PostHistoryTypeId = 10
),
-- 14) Map close reason to name
close_reason as (
    select
        qcr.QuestionId,
        crt.Name as CloseReasonName
    from question_close_reason qcr
    left join CloseReasonTypes crt on crt.Id = qcr.CloseReasonId
),
-- 15) Compose user info for owners
owner_info as (
    select
        ub.UserId,
        ub.DisplayName,
        ub.Reputation,
        ub.Location,
        (ub.UpVotes - ub.DownVotes) as NetVotes,
        coalesce(ba.GoldBadges,0) as GoldBadges,
        coalesce(ba.SilverBadges,0) as SilverBadges,
        coalesce(ba.BronzeBadges,0) as BronzeBadges,
        coalesce(ba.TagBadges,0) as TagBadges
    from user_base ub
    left join user_badge_agg ba on ba.UserId = ub.UserId
),
-- 16) Null and string handling showcase
title_signals as (
    select
        qr.QuestionId,
        length(coalesce(qr.Title, '')) as TitleLen,
        -- signal words presence
        (position('how to' in lower(coalesce(qr.Title,''))) > 0)::int as HasHowTo,
        (position('why' in lower(coalesce(qr.Title,''))) > 0)::int as HasWhy,
        (position('help' in lower(coalesce(qr.Title,''))) > 0)::int as HasHelp,
        regexp_count(coalesce(qr.Title,''), '\?') as QMarkCnt
    from question_ranks qr
),
-- 17) Bring in link characteristics (duplicates/linked counts)
link_summary as (
    select
        ql.SrcId as QuestionId,
        sum(case when ql.LinkType = 'Duplicate' then ql.LinkCount else 0 end) as OutDupCnt,
        sum(case when ql.LinkType = 'Linked' then ql.LinkCount else 0 end) as OutLinkCnt,
        sum(case when ql.LinkType = 'Duplicate' and ql.DstId <> ql.SrcId then 1 else 0 end) as DistinctDupTargets
    from q_links ql
    group by ql.SrcId
),
-- 18) Combine everything and compute a composite benchmark score
final_scores as (
    select
        qr.QuestionId,
        qr.RankOverall,
        qr.RankByAnswers,
        qr.RankByViews,
        qr.ViewPercentile,
        qr.QualityDecile,
        qr.QualityScore,
        qr.NetVotesAll,
        qr.Score as QuestionScore,
        qr.ViewCount,
        qr.AnswerCount,
        oi.UserId as OwnerUserId,
        oi.DisplayName as OwnerDisplayName,
        oi.Reputation as OwnerReputation,
        oi.Location as OwnerLocation,
        oi.NetVotes as OwnerNetVotes,
        (oi.GoldBadges*5 + oi.SilverBadges*2 + oi.BronzeBadges) as OwnerBadgeScore,
        coalesce(qtt.TopTag, '(none)') as TopTag,
        coalesce(cr.CloseReasonName, '(open)') as CloseReason,
        coalesce(ls.OutDupCnt,0) as OutDupCnt,
        coalesce(ls.OutLinkCnt,0) as OutLinkCnt,
        coalesce(ls.DistinctDupTargets,0) as DistinctDupTargets,
        ts.TitleLen,
        ts.HasHowTo,
        ts.HasWhy,
        ts.HasHelp,
        ts.QMarkCnt,
        -- composite benchmark score (floating point)
        (
            qr.QualityScore
            + (greatest(qr.ViewCount,0) / 500.0)
            + coalesce(qr.AnswerCount,0) * 1.5
            + least(coalesce(qr.NetVotesAll,0), 500)
            + (case when cr.CloseReasonName is null or cr.CloseReasonName = '(open)' then 10 else -25 end)
            + (case when ts.QMarkCnt > 0 then 2 else 0 end)
            + (case when ts.HasHowTo = 1 then 3 else 0 end)
            + (case when ts.HasHelp = 1 then -1 else 0 end)
            + (oi.Reputation / 200.0)
            + (oi.GoldBadges*2 + oi.SilverBadges*1 + oi.BronzeBadges*0.25)
            - (coalesce(ls.OutDupCnt,0) * 0.5)
        ) as BenchmarkScore
    from question_ranks qr
    left join owner_info oi on oi.UserId = qr.OwnerUserId
    left join question_top_tag qtt on qtt.QuestionId = qr.QuestionId
    left join close_reason cr on cr.QuestionId = qr.QuestionId
    left join link_summary ls on ls.QuestionId = qr.QuestionId
    left join title_signals ts on ts.QuestionId = qr.QuestionId
),
-- 19) Partition by top tag for intra-tag ranking
tag_ranked as (
    select
        fs.*,
        row_number() over (partition by TopTag order by BenchmarkScore desc, RankOverall asc) as RankInTag,
        avg(BenchmarkScore) over (partition by TopTag) as AvgTagScore
    from final_scores fs
),
-- 20) Correlated subqueries for accepted answer owner context and favorite count peers
accepted_answer_owner as (
    select
        q.QuestionId,
        (
            select u.DisplayName
            from Posts a
            left join Users u on u.Id = a.OwnerUserId
            where a.Id = q.AcceptedAnswerId
        ) as AcceptedAnswerOwner
    from recent_questions q
),
fav_peers as (
    select
        q.QuestionId,
        (
            select avg(coalesce(p.FavoriteCount,0))::numeric(12,2)
            from Posts p
            where p.PostTypeId = 1
              and p.CreationDate >= (select from_date from params)
              and p.FavoriteCount is not null
        ) as AvgFavoritesRecent
    from recent_questions q
)
select
    tr.QuestionId,
    left(coalesce(q.Title,''), 120) as TitleSnippet,
    tr.TopTag,
    tr.RankOverall,
    tr.RankInTag,
    tr.QualityDecile,
    tr.BenchmarkScore::numeric(18,2) as BenchmarkScore,
    tr.QualityScore,
    tr.NetVotesAll,
    tr.QuestionScore,
    tr.ViewCount,
    tr.AnswerCount,
    tr.OutDupCnt,
    tr.OutLinkCnt,
    tr.DistinctDupTargets,
    tr.TitleLen,
    tr.HasHowTo,
    tr.HasWhy,
    tr.HasHelp,
    tr.QMarkCnt,
    tr.OwnerUserId,
    tr.OwnerDisplayName,
    tr.OwnerReputation,
    tr.OwnerLocation,
    tr.OwnerNetVotes,
    tr.OwnerBadgeScore,
    coalesce(aao.AcceptedAnswerOwner, '(none)') as AcceptedAnswerOwner,
    coalesce(cr.CloseReason, '(open)') as CloseReason,
    tp.q_per_tag as RecentQPerTopTag,
    fp.AvgFavoritesRecent
from tag_ranked tr
join recent_questions q on q.QuestionId = tr.QuestionId
left join accepted_answer_owner aao on aao.QuestionId = tr.QuestionId
left join fav_peers fp on fp.QuestionId = tr.QuestionId
left join tag_stats tp on tp.tag_name = tr.TopTag
left join close_reason cr on cr.QuestionId = tr.QuestionId
cross join params par
where tr.OwnerReputation >= par.min_rep
  and tr.RankOverall <= 500
  and (tr.BenchmarkScore > 0 or tr.QualityDecile <= 3)
order by tr.BenchmarkScore desc, tr.RankOverall asc, tr.QuestionId asc;