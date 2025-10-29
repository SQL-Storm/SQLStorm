-- {"query": "831.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2819}
with recent_questions as (
    select
        q.Id as QuestionId,
        q.CreationDate,
        q.OwnerUserId,
        coalesce(q.Score, 0) as Score,
        coalesce(q.ViewCount, 0) as ViewCount,
        q.Title,
        q.Tags,
        q.AcceptedAnswerId,
        q.AnswerCount,
        q.CommentCount,
        q.ClosedDate
    from Posts q
    where q.PostTypeId = 1
      and q.CreationDate >= (select max(CreationDate) - interval '90' day from Posts where PostTypeId = 1)
),
question_tag as (
    select
        rq.QuestionId,
        lower(trim(t.tag)) as tag
    from recent_questions rq,
         lateral (
             select unnest(string_to_array(substring(rq.Tags, 2, greatest(length(rq.Tags)-2,0)), '><')) as tag
         ) t
),
tag_stats as (
    select
        qt.tag,
        count(distinct qt.QuestionId) as question_count,
        sum(rq.ViewCount) as total_views,
        avg(nullif(rq.Score, 0)) as avg_nonzero_score,
        sum(case when rq.AcceptedAnswerId is not null then 1 else 0 end) as accepted_cnt
    from question_tag qt
    join recent_questions rq on rq.QuestionId = qt.QuestionId
    group by qt.tag
    having count(distinct qt.QuestionId) >= 5
),
user_activity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate as UserCreated,
        u.LastAccessDate,
        u.UpVotes,
        u.DownVotes,
        coalesce(u.Views, 0) as ProfileViews
    from Users u
),
answers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate
    from Posts a
    where a.PostTypeId = 2
),
agg_answers as (
    select
        a.QuestionId,
        count(*) as answer_cnt,
        max(a.Score) as max_answer_score,
        avg(a.Score) as avg_answer_score,
        sum(case when a.Score > 0 then 1 else 0 end) as positive_answers,
        min(a.CreationDate) as first_ans_time
    from answers a
    group by a.QuestionId
),
dup_links as (
    select
        pl.PostId as QuestionId,
        sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as duplicate_links,
        sum(case when pl.LinkTypeId = 1 then 1 else 0 end) as linked_links
    from PostLinks pl
    group by pl.PostId
),
question_votes as (
    select
        v.PostId as QuestionId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as upvotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as downvotes,
        sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as bounty_sum
    from Votes v
    group by v.PostId
),
first_close_event as (
    select
        ph.PostId as QuestionId,
        ph.CreationDate as close_created,
        ph.Comment as close_reason_raw
    from PostHistory ph
    where ph.PostHistoryTypeId = 10
    and ph.CreationDate = (
        select min(ph2.CreationDate)
        from PostHistory ph2
        where ph2.PostId = ph.PostId and ph2.PostHistoryTypeId = 10
    )
),
close_reason_labeled as (
    select
        f.QuestionId,
        f.close_created,
        case
            when nullif(trim(f.close_reason_raw), '') is null then 'Unknown'
            when f.close_reason_raw ~ '^[0-9]+$' and f.close_reason_raw is not null then
                coalesce(crt.Name, 'ReasonId:' || f.close_reason_raw)
            else f.close_reason_raw
        end as close_reason
    from first_close_event f
    left join CloseReasonTypes crt
      on (case when f.close_reason_raw ~ '^[0-9]+$' then cast(f.close_reason_raw as integer) else null end) = crt.Id
),
question_comments as (
    select
        c.PostId as QuestionId,
        count(*) as comment_cnt,
        max(c.Score) as max_comment_score,
        avg(c.Score) as avg_comment_score
    from Comments c
    group by c.PostId
),
question_owner as (
    select
        rq.QuestionId,
        u.UserId,
        u.DisplayName,
        u.Reputation,
        u.ProfileViews,
        u.UpVotes,
        u.DownVotes,
        floor(
          extract(epoch from (timestamp '2024-10-01 12:34:56' - u.UserCreated)) / (365.25*24*3600)
        ) as acct_age_years
    from recent_questions rq
    left join user_activity u on u.UserId = rq.OwnerUserId
),
ranked_questions as (
    select
        rq.QuestionId,
        rq.Title,
        rq.CreationDate,
        rq.Score,
        rq.ViewCount,
        rq.AcceptedAnswerId,
        rq.AnswerCount,
        rq.CommentCount,
        rq.ClosedDate,
        qo.DisplayName as OwnerName,
        qo.Reputation as OwnerRep,
        qo.acct_age_years,
        qa.upvotes,
        qa.downvotes,
        qa.bounty_sum,
        coalesce(da.duplicate_links,0) as duplicate_links,
        coalesce(da.linked_links,0) as linked_links,
        coalesce(aa.answer_cnt,0) as answer_cnt,
        coalesce(aa.max_answer_score,NULL) as max_answer_score,
        coalesce(aa.avg_answer_score,NULL) as avg_answer_score,
        qc.comment_cnt,
        qc.max_comment_score,
        qc.avg_comment_score,
        cr.close_reason,
        cr.close_created,
        row_number() over (order by rq.ViewCount desc, rq.Score desc, rq.CreationDate desc) as rn_views,
        row_number() over (order by rq.Score desc, rq.ViewCount desc, rq.CreationDate desc) as rn_score,
        dense_rank() over (order by coalesce(qa.upvotes,0) - coalesce(qa.downvotes,0) desc) as dr_netvotes,
        percent_rank() over (order by coalesce(aa.answer_cnt,0)) as pr_answer_cnt
    from recent_questions rq
    left join question_owner qo on qo.QuestionId = rq.QuestionId
    left join question_votes qa on qa.QuestionId = rq.QuestionId
    left join dup_links da on da.QuestionId = rq.QuestionId
    left join agg_answers aa on aa.QuestionId = rq.QuestionId
    left join question_comments qc on qc.QuestionId = rq.QuestionId
    left join close_reason_labeled cr on cr.QuestionId = rq.QuestionId
),
tag_enriched as (
    select
        qt.QuestionId,
        qt.tag,
        ts.question_count as tag_q_count,
        ts.total_views as tag_total_views,
        ts.avg_nonzero_score as tag_avg_nz_score,
        ts.accepted_cnt as tag_accepted_cnt
    from question_tag qt
    left join tag_stats ts on ts.tag = qt.tag
),
question_tag_rollup as (
    select
        te.QuestionId,
        count(*) as tag_cnt,
        max(te.tag_q_count) as max_tag_popularity,
        avg(te.tag_q_count) as avg_tag_popularity,
        sum(coalesce(te.tag_total_views,0)) as sum_tag_views,
        max(te.tag_avg_nz_score) as max_tag_avg_nz_score,
        sum(case when coalesce(te.tag_accepted_cnt,0) > 0 then 1 else 0 end) as tags_with_accepts
    from tag_enriched te
    group by te.QuestionId
),
owner_badges as (
    select
        b.UserId,
        count(*) as badge_total,
        sum(case when b.Class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.Class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.Class = 3 then 1 else 0 end) as bronze_badges,
        sum(case when b.TagBased = true then 1 else 0 end) as tag_badges
    from Badges b
    group by b.UserId
),
final_scored as (
    select
        rq.QuestionId,
        rq.Title,
        rq.CreationDate,
        rq.Score,
        rq.ViewCount,
        rq.OwnerName,
        rq.OwnerRep,
        rq.acct_age_years,
        rq.upvotes,
        rq.downvotes,
        rq.bounty_sum,
        rq.answer_cnt,
        rq.max_answer_score,
        rq.avg_answer_score,
        rq.comment_cnt,
        rq.max_comment_score,
        rq.avg_comment_score,
        rq.duplicate_links,
        rq.linked_links,
        rq.close_reason,
        rq.close_created,
        qtr.tag_cnt,
        qtr.max_tag_popularity,
        qtr.avg_tag_popularity,
        qtr.sum_tag_views,
        qtr.max_tag_avg_nz_score,
        qtr.tags_with_accepts,
        ob.badge_total,
        ob.gold_badges,
        ob.silver_badges,
        ob.bronze_badges,
        ob.tag_badges,
        rq.rn_views,
        rq.rn_score,
        rq.dr_netvotes,
        rq.pr_answer_cnt,
        (
            coalesce(rq.ViewCount,0) * 0.002
          + coalesce(rq.Score,0) * 0.9
          + coalesce(rq.upvotes,0) * 0.15
          - coalesce(rq.downvotes,0) * 0.2
          + coalesce(rq.answer_cnt,0) * 0.35
          + coalesce(rq.max_answer_score,0) * 0.2
          + coalesce(rq.comment_cnt,0) * 0.05
          + least(coalesce(qtr.tag_cnt,0), 5) * 0.25
          + coalesce(ob.gold_badges,0) * 0.4
          + coalesce(ob.silver_badges,0) * 0.2
          + coalesce(ob.bronze_badges,0) * 0.1
          + case when rq.AcceptedAnswerId is not null then 1.0 else 0.0 end
          + case when rq.ClosedDate is not null then -1.5 else 0.0 end
          + case when rq.duplicate_links > 0 then -0.75 else 0.0 end
          + case when rq.bounty_sum > 0 then 0.5 + least(rq.bounty_sum, 500) / 1000.0 else 0.0 end
        ) as perf_score,
        trim(
            coalesce(rq.Title, '') || ' | by ' ||
            coalesce(rq.OwnerName, '[unknown]') || ' (' ||
            coalesce(cast(rq.OwnerRep as varchar), '0') || ' rep)' ||
            case when rq.close_reason is not null then ' [Closed: ' || rq.close_reason || ']' else '' end
        ) as summary
    from ranked_questions rq
    left join question_tag_rollup qtr on qtr.QuestionId = rq.QuestionId
    left join owner_badges ob on ob.UserId = (
        select p.OwnerUserId from Posts p where p.Id = rq.QuestionId
    )
),
top_vs_recent as (
    select
        fs.*,
        ntile(10) over (order by fs.perf_score desc) as decile,
        count(*) over () as total_rows
    from final_scored fs
)
select
    tvr.QuestionId,
    tvr.Title,
    tvr.OwnerName,
    tvr.OwnerRep,
    tvr.Score,
    tvr.ViewCount,
    tvr.upvotes,
    tvr.downvotes,
    tvr.answer_cnt,
    tvr.comment_cnt,
    tvr.duplicate_links,
    tvr.linked_links,
    tvr.close_reason,
    tvr.tag_cnt,
    tvr.max_tag_popularity,
    tvr.avg_tag_popularity,
    tvr.sum_tag_views,
    tvr.badge_total,
    tvr.gold_badges,
    tvr.silver_badges,
    tvr.bronze_badges,
    tvr.tag_badges,
    tvr.rn_views,
    tvr.rn_score,
    tvr.dr_netvotes,
    round(tvr.pr_answer_cnt, 4) as pr_answer_cnt,
    round(tvr.perf_score, 3) as perf_score,
    tvr.decile,
    tvr.summary
from top_vs_recent tvr
where (
        tvr.decile in (1,2)
        or tvr.rn_views <= 50
        or (tvr.OwnerRep >= 10000 and tvr.Score >= 5)
      )
  and coalesce(tvr.tag_cnt,0) >= 1
  and not exists (
        select 1
        from PostHistory ph
        where ph.PostId = tvr.QuestionId
          and ph.PostHistoryTypeId in (12)
    )
order by
    tvr.decile asc,
    tvr.perf_score desc,
    tvr.rn_views asc,
    tvr.QuestionId asc
limit 200;