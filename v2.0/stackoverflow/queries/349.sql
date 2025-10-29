-- {"query": "349.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3142}
with recent_questions as (
    select
        p.Id as QuestionId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.Title,
        p.Tags,
        coalesce(p.AnswerCount, 0) as AnswerCount
    from Posts p
    where p.PostTypeId = 1
      and p.CreationDate >= (select max(CreationDate) - interval '365 days' from Posts where PostTypeId = 1)
),
question_tag as (
    select
        q.QuestionId,
        unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) as tag
    from recent_questions q
    where q.Tags is not null
),
tag_stats as (
    select
        qt.tag,
        count(distinct qt.QuestionId) as q_cnt,
        avg(cast(q.Score as numeric)) as avg_q_score,
        avg(cast(q.ViewCount as numeric)) as avg_q_views
    from question_tag qt
    join recent_questions q on q.QuestionId = qt.QuestionId
    group by qt.tag
    having count(distinct qt.QuestionId) > 10
),
user_activity as (
    select
        u.Id as UserId,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate as UserCreationDate,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end), 0) as NetVotesCast,
        count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges
    from Users u
    left join Votes v on v.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.Reputation, u.UpVotes, u.DownVotes, u.CreationDate
),
answerers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswererId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        case when a.Id = q.AcceptedAnswerId then 1 else 0 end as IsAccepted
    from Posts a
    join recent_questions q on q.QuestionId = a.ParentId
    where a.PostTypeId = 2
),
question_votes as (
    select
        v.PostId as QuestionId,
        sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end) as NetVotes,
        count(*) filter (where v.VoteTypeId = 5) as FavoriteCountLegacy
    from Votes v
    join recent_questions q on q.QuestionId = v.PostId
    group by v.PostId
),
close_events as (
    select
        ph.PostId as QuestionId,
        min(ph.CreationDate) as FirstClosedAt,
        max(ph.CreationDate) as LastClosedAt,
        count(*) as CloseEventCount,
        count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenEventCount,
        max(case when ph.PostHistoryTypeId = 10 then ph.Comment end) as LastCloseReasonIdRaw
    from PostHistory ph
    join recent_questions q on q.QuestionId = ph.PostId
    where ph.PostHistoryTypeId in (10,11)
    group by ph.PostId
),
dup_links as (
    select
        pl.PostId as DuplicateOfQuestionId,
        count(*) filter (where pl.LinkTypeId = 3) as DuplicateRefs,
        count(*) filter (where pl.LinkTypeId = 1) as LinkedRefs
    from PostLinks pl
    group by pl.PostId
),
commenter_stats as (
    select
        c.PostId as QuestionId,
        count(*) as CommentCount,
        max(c.Score) as MaxCommentScore,
        count(*) filter (where c.Score > 0) as PositiveComments
    from Comments c
    join recent_questions q on q.QuestionId = c.PostId
    group by c.PostId
),
owner_user_enriched as (
    select
        q.QuestionId,
        u.UserId,
        u.Reputation,
        u.NetVotesCast,
        u.GoldBadges,
        u.SilverBadges,
        u.BronzeBadges,
        extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - u.UserCreationDate)) / 86400.0 as UserAgeDays
    from recent_questions q
    left join user_activity u on u.UserId = q.OwnerUserId
),
question_quality as (
    select
        q.QuestionId,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        coalesce(qv.NetVotes, 0) as NetVotes,
        coalesce(qv.FavoriteCountLegacy, 0) as FavoriteCountLegacy,
        coalesce(ce.CloseEventCount, 0) as CloseEventCount,
        coalesce(ce.ReopenEventCount, 0) as ReopenEventCount,
        ce.FirstClosedAt,
        ce.LastClosedAt,
        coalesce(dl.DuplicateRefs, 0) as DuplicateRefs,
        coalesce(dl.LinkedRefs, 0) as LinkedRefs,
        coalesce(cs.CommentCount, 0) as CommentCount,
        coalesce(cs.MaxCommentScore, 0) as MaxCommentScore,
        coalesce(cs.PositiveComments, 0) as PositiveComments,
        oue.Reputation as OwnerReputation,
        oue.NetVotesCast as OwnerNetVotesCast,
        oue.GoldBadges,
        oue.SilverBadges,
        oue.BronzeBadges,
        oue.UserAgeDays,
        case
            when q.Score >= 10 and q.ViewCount >= 10000 then 'Hero'
            when q.Score < 0 and coalesce(ce.CloseEventCount,0) > 0 then 'Controversial'
            when q.AnswerCount = 0 and q.ViewCount < 100 then 'Neglected'
            else 'Normal'
        end as QualityBucket
    from recent_questions q
    left join question_votes qv on qv.QuestionId = q.QuestionId
    left join close_events ce on ce.QuestionId = q.QuestionId
    left join dup_links dl on dl.DuplicateOfQuestionId = q.QuestionId
    left join commenter_stats cs on cs.QuestionId = q.QuestionId
    left join owner_user_enriched oue on oue.QuestionId = q.QuestionId
),
accepted_answerers as (
    select
        a.QuestionId,
        a.AnswererId as AcceptedAnswererId,
        a.AnswerScore as AcceptedAnswerScore,
        a.AnswerCreationDate as AcceptedAnswerCreationDate
    from answerers a
    where a.IsAccepted = 1
),
first_answer as (
    select distinct on (a.QuestionId)
        a.QuestionId,
        a.AnswerId as FirstAnswerId,
        a.AnswererId as FirstAnswererId,
        a.AnswerScore as FirstAnswerScore,
        a.AnswerCreationDate as FirstAnswerCreationDate
    from answerers a
    order by a.QuestionId, a.AnswerCreationDate asc, a.AnswerId asc
),
per_tag_question_rank as (
    select
        qq.QuestionId,
        qt.tag,
        qq.Score,
        qq.ViewCount,
        row_number() over (partition by qt.tag order by qq.Score desc, qq.ViewCount desc, qq.QuestionId) as rank_in_tag,
        dense_rank() over (partition by qt.tag order by qq.ViewCount desc) as view_rank_in_tag
    from question_quality qq
    join question_tag qt on qt.QuestionId = qq.QuestionId
),
question_tag_agg as (
    select
        pqr.QuestionId,
        array_agg(pqr.tag order by pqr.rank_in_tag asc) as tags_by_score,
        min(pqr.rank_in_tag) as best_rank_in_any_tag,
        min(pqr.view_rank_in_tag) as best_view_rank_in_any_tag
    from per_tag_question_rank pqr
    group by pqr.QuestionId
),
owner_v_answerer as (
    select
        qq.QuestionId,
        case when qq.OwnerReputation is null then null
             else qq.OwnerReputation end as OwnerRep,
        case when ua.Reputation is null then null
             else ua.Reputation end as AcceptedAnswererRep,
        case
            when qq.OwnerReputation is not null and ua.Reputation is not null
            then qq.OwnerReputation - ua.Reputation
            else null
        end as RepDeltaOwnerMinusAccepted
    from question_quality qq
    left join accepted_answerers aa on aa.QuestionId = qq.QuestionId
    left join Users uacc on uacc.Id = aa.AcceptedAnswererId
    left join user_activity ua on ua.UserId = uacc.Id
),
license_inference as (
    select
        p.Id as PostId,
        coalesce(nullif(trim(p.ContentLicense), ''), 'unknown') as LicenseNorm
    from Posts p
    where p.PostTypeId in (1,2)
),
hot_candidates as (
    select
        qq.QuestionId,
        qq.Title,
        qq.ViewCount,
        qq.Score,
        qq.AnswerCount,
        qq.CommentCount,
        qq.QualityBucket,
        qt.tags_by_score,
        qt.best_rank_in_any_tag,
        qt.best_view_rank_in_any_tag,
        ov.RepDeltaOwnerMinusAccepted,
        aa.AcceptedAnswererId,
        fa.FirstAnswerId,
        case
            when qq.Score >= 5 and qq.ViewCount >= 5000 and qq.AnswerCount >= 2 then 1
            when qq.Score >= 3 and qq.ViewCount >= 3000 and qq.AnswerCount >= 1 and qq.CommentCount >= 3 then 1
            else 0
        end as IsHotCandidate
    from question_quality qq
    left join question_tag_agg qt on qt.QuestionId = qq.QuestionId
    left join owner_v_answerer ov on ov.QuestionId = qq.QuestionId
    left join accepted_answerers aa on aa.QuestionId = qq.QuestionId
    left join first_answer fa on fa.QuestionId = qq.QuestionId
),
normalized as (
    select
        hc.QuestionId,
        hc.Title,
        hc.ViewCount,
        hc.Score,
        hc.AnswerCount,
        hc.CommentCount,
        hc.QualityBucket,
        hc.tags_by_score,
        hc.best_rank_in_any_tag,
        hc.best_view_rank_in_any_tag,
        hc.RepDeltaOwnerMinusAccepted,
        hc.AcceptedAnswererId,
        hc.FirstAnswerId,
        hc.IsHotCandidate,
        (cast(hc.Score as numeric) / nullif(hc.ViewCount,0)) as score_per_view,
        (cast(hc.AnswerCount as numeric) / nullif(hc.ViewCount,0)) as answers_per_view,
        (case when array_length(hc.tags_by_score, 1) is null then 0 else array_length(hc.tags_by_score, 1) end) as tag_count
    from hot_candidates hc
),
-- Replace ordered-set percentile_cont with percentile approximation using windowed NTILE approach to be more portable.
score_percentiles as (
    select
        n.QuestionId,
        max(case when ntile_100 <= 90 then n.Score end) as p90_score,
        max(case when ntile_100 <= 75 then n.Score end) as p75_score
    from (
        select
            n.*,
            ntile(100) over (order by n.Score) as ntile_100
        from normalized n
    ) n
    group by n.QuestionId
),
final_scores as (
    select
        n.QuestionId,
        n.Title,
        n.ViewCount,
        n.Score,
        n.AnswerCount,
        n.CommentCount,
        n.QualityBucket,
        n.tags_by_score,
        n.best_rank_in_any_tag,
        n.best_view_rank_in_any_tag,
        n.RepDeltaOwnerMinusAccepted,
        n.AcceptedAnswererId,
        n.FirstAnswerId,
        n.IsHotCandidate,
        n.score_per_view,
        n.answers_per_view,
        n.tag_count,
        (coalesce(n.Score,0) * 1.0)
        + (least(coalesce(n.ViewCount,0), 50000) / 100.0)
        + (coalesce(n.AnswerCount,0) * 2.5)
        + (coalesce(n.CommentCount,0) * 0.5)
        + (case when n.QualityBucket = 'Hero' then 50 when n.QualityBucket = 'Controversial' then -25 when n.QualityBucket = 'Neglected' then -10 else 0 end)
        - (greatest(coalesce(n.best_rank_in_any_tag, 1000) - 10, 0) * 0.2)
        - (greatest(coalesce(n.best_view_rank_in_any_tag, 1000) - 10, 0) * 0.1)
        + (case when n.IsHotCandidate = 1 then 30 else 0 end)
        + (least(coalesce(n.tag_count,0), 5) * 1.0)
        + (case when n.score_per_view is not null then least(n.score_per_view * 1000.0, 20.0) else 0 end)
        + (case when n.answers_per_view is not null then least(n.answers_per_view * 500.0, 15.0) else 0 end)
        + (case when n.RepDeltaOwnerMinusAccepted is not null and n.RepDeltaOwnerMinusAccepted < 0 then 5 else 0 end)
        as BenchmarkScore
    from normalized n
)
select
    fs.QuestionId,
    fs.Title,
    fs.BenchmarkScore,
    fs.QualityBucket,
    fs.ViewCount,
    fs.Score,
    fs.AnswerCount,
    fs.CommentCount,
    fs.tags_by_score,
    fs.best_rank_in_any_tag,
    fs.best_view_rank_in_any_tag,
    fs.RepDeltaOwnerMinusAccepted,
    fs.AcceptedAnswererId,
    fs.FirstAnswerId,
    lic.LicenseNorm,
    ts.tag as TopTagByAvgScore,
    ts.avg_q_score as TopTagAvgScore,
    row_number() over (order by fs.BenchmarkScore desc, fs.Score desc, fs.ViewCount desc) as OverallRank
from final_scores fs
left join license_inference lic on lic.PostId = fs.QuestionId
left join lateral (
    select t.tag, t.avg_q_score
    from tag_stats t
    join question_tag qt on qt.tag = t.tag and qt.QuestionId = fs.QuestionId
    order by t.avg_q_score desc nulls last, t.tag asc
    limit 1
) ts on true
where fs.BenchmarkScore is not null
and 1 = 1
order by fs.BenchmarkScore desc, fs.Score desc, fs.ViewCount desc
limit 200;