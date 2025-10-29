-- {"query": "458.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2888}
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
        date_trunc('month', u.creationdate) as cohort_month,
        count(b.id) filter (where b.class = 1) as gold_badges,
        count(b.id) filter (where b.class = 2) as silver_badges,
        count(b.id) filter (where b.class = 3) as bronze_badges,
        count(*) over () as total_users_window
    from users u
    left join badges b
      on b.userid = u.id
     and b.date >= u.creationdate
    where u.creationdate >= (select coalesce(max(creationdate), timestamp '1900-01-01') from users) - interval '3 years'
    group by u.id, u.displayname, u.reputation, u.creationdate, u.location, u.websiteurl
),
tagged_questions as (
    select
        p.id as question_id,
        p.owneruserid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.answercount,
        p.title,
        p.tags,
        string_to_array(substring(p.tags, 2, char_length(p.tags)-2), '><') as tag_array
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= (select coalesce(max(creationdate), timestamp '1900-01-01') from posts where posttypeid = 1) - interval '3 years'
),
answers as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as answerer_id,
        a.creationdate as answer_created,
        a.score as answer_score
    from posts a
    where a.posttypeid = 2
),
votes_agg as (
    select
        v.postid,
        count(*) filter (where v.votetypeid = 2) as upvotes,
        count(*) filter (where v.votetypeid = 3) as downvotes,
        count(*) filter (where v.votetypeid = 5) as favorites,
        sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_total
    from votes v
    where v.creationdate >= (select coalesce(max(creationdate), timestamp '1900-01-01') from votes) - interval '3 years'
    group by v.postid
),
postlink_dups as (
    select
        pl.postid as dup_post_id,
        pl.relatedpostid as canonical_post_id,
        min(pl.creationdate) as first_dup_date
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid, pl.relatedpostid
),
close_events as (
    select
        ph.postid,
        min(ph.creationdate) as first_close_date,
        max(ph.creationdate) as last_close_date,
        count(*) as close_events,
        count(*) filter (where ph.comment = '101') as duplicate_votes,
        count(*) filter (where ph.comment = '102') as offtopic_votes,
        count(*) filter (where ph.comment = '103') as needs_detail_votes,
        count(*) filter (where ph.comment = '104') as needs_focus_votes,
        count(*) filter (where ph.comment = '105') as opinion_based_votes
    from posthistory ph
    where ph.posthistorytypeid in (10,35)
    group by ph.postid
),
edit_stats as (
    select
        ph.postid,
        count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edits,
        min(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as first_edit,
        max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as last_edit
    from posthistory ph
    group by ph.postid
),
comment_stats as (
    select
        c.postid,
        count(*) as comment_count,
        avg(c.score) as avg_comment_score,
        max(c.creationdate) as last_comment_date
    from comments c
    group by c.postid
),
question_enriched as (
    select
        q.question_id,
        q.owneruserid as asker_id,
        q.creationdate as question_created,
        q.score as question_score,
        q.viewcount,
        q.answercount,
        q.title,
        q.tags,
        q.tag_array,
        va.upvotes,
        va.downvotes,
        va.favorites,
        va.bounty_total,
        ce.first_close_date,
        ce.last_close_date,
        ce.close_events,
        coalesce(ce.duplicate_votes,0) as duplicate_votes,
        es.edits,
        es.first_edit,
        es.last_edit,
        cs.comment_count,
        cs.avg_comment_score,
        cs.last_comment_date,
        pd.canonical_post_id,
        pd.first_dup_date
    from tagged_questions q
    left join votes_agg va on va.postid = q.question_id
    left join close_events ce on ce.postid = q.question_id
    left join edit_stats es on es.postid = q.question_id
    left join comment_stats cs on cs.postid = q.question_id
    left join postlink_dups pd on pd.dup_post_id = q.question_id
),
answer_agg as (
    select
        a.question_id,
        count(*) as answers_total,
        count(*) filter (where a.answer_score > 0) as positive_answers,
        max(a.answer_score) as best_answer_score,
        min(a.answer_created) as first_answer_date
    from answers a
    group by a.question_id
),
owner_stats as (
    select
        u.id as user_id,
        count(p.id) filter (where p.posttypeid = 1) as questions_asked,
        count(p.id) filter (where p.posttypeid = 2) as answers_given,
        sum(p.score) filter (where p.posttypeid = 1) as question_score_sum,
        sum(p.score) filter (where p.posttypeid = 2) as answer_score_sum,
        max(p.creationdate) as last_post_date
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
tag_expansion as (
    select
        qe.*,
        unnest(qe.tag_array) as tagname
    from question_enriched qe
),
tag_rank as (
    select
        tagname,
        count(*) as tag_questions,
        avg(coalesce(question_score,0)) as avg_tag_score
    from tag_expansion
    group by tagname
),
score_buckets as (
    select
        qe.question_id,
        case
            when qe.question_score >= 50 then '50+'
            when qe.question_score >= 20 then '20-49'
            when qe.question_score >= 10 then '10-19'
            when qe.question_score >= 0 then '0-9'
            when qe.question_score >= -5 then '-5 - -1'
            else '< -5'
        end as score_bucket
    from question_enriched qe
),
final_set as (
    select
        qe.question_id,
        qe.asker_id,
        ru.displayname as asker_name,
        ru.reputation,
        ru.cohort_month,
        os.questions_asked,
        os.answers_given,
        os.last_post_date,
        qe.question_created,
        qe.title,
        qe.tags,
        qe.viewcount,
        qe.question_score,
        qe.upvotes,
        qe.downvotes,
        qe.favorites,
        qe.bounty_total,
        qe.edits,
        qe.first_edit,
        qe.last_edit,
        qe.comment_count,
        qe.avg_comment_score,
        qe.first_close_date,
        qe.last_close_date,
        qe.close_events,
        qe.duplicate_votes,
        qe.canonical_post_id,
        qe.first_dup_date,
        aa.answers_total,
        aa.positive_answers,
        aa.best_answer_score,
        aa.first_answer_date,
        sb.score_bucket,
        dense_rank() over (partition by sb.score_bucket order by qe.viewcount desc nulls last, qe.question_created desc) as bucket_view_rank,
        row_number() over (order by qe.question_score desc nulls last, qe.viewcount desc nulls last) as global_rownum,
        count(*) over () as total_rows_window
    from question_enriched qe
    left join answer_agg aa on aa.question_id = qe.question_id
    left join recent_users ru on ru.user_id = qe.asker_id
    left join owner_stats os on os.user_id = qe.asker_id
    left join score_buckets sb on sb.question_id = qe.question_id
),
top_per_bucket as (
    select *
    from final_set
    where bucket_view_rank <= 50
),
dedup_canonical as (
    select
        f.*,
        case
            when f.canonical_post_id is not null then
                (select p.title from posts p where p.id = f.canonical_post_id)
            else null
        end as canonical_title
    from top_per_bucket f
),
quality_flag as (
    select
        d.*,
        (
            (coalesce(d.question_score,0) * 2)
            + (coalesce(d.upvotes,0) - coalesce(d.downvotes,0))
            + (case when d.positive_answers >= 1 then 5 else 0 end)
            + (case when d.edits >= 3 then 2 else 0 end)
            + (case when d.comment_count >= 5 then 1 else 0 end)
            - (case when d.close_events >= 1 then 7 else 0 end)
            - (case when d.duplicate_votes >= 1 then 4 else 0 end)
            + (case when d.viewcount >= 10000 then 3 when d.viewcount >= 1000 then 1 else 0 end)
        ) as quality_score
    from dedup_canonical d
),
with_null_logic as (
    select
        qf.*,
        coalesce(nullif(trim(qf.tags), ''), '<untagged>') as tags_safe,
        coalesce(qf.canonical_title, case when qf.canonical_post_id is not null then '[missing canonical title]' else null end) as canonical_title_safe,
        coalesce(qf.asker_name, '[user-deleted]') as asker_name_safe
    from quality_flag qf
),
ranked as (
    select
        w.*,
        mq.quality_median,
        ntile(10) over (order by quality_score desc nulls last) as quality_decile,
        sum(case when answers_total > 0 then 1 else 0 end) over (partition by score_bucket) as bucket_answered_count
    from with_null_logic w
    join (
        select percentile_cont(0.5) within group (order by quality_score) as quality_median
        from with_null_logic
    ) mq on true
)
select
    r.score_bucket,
    r.quality_decile,
    r.question_id,
    r.title,
    r.tags_safe as tags,
    r.asker_id,
    r.asker_name_safe as asker_name,
    r.reputation,
    r.cohort_month,
    r.viewcount,
    r.question_score,
    r.upvotes,
    r.downvotes,
    r.favorites,
    r.bounty_total,
    r.answers_total,
    r.best_answer_score,
    r.first_answer_date,
    r.edits,
    r.comment_count,
    r.first_close_date,
    r.canonical_post_id,
    r.canonical_title_safe as canonical_title,
    r.quality_score,
    r.quality_median,
    r.bucket_view_rank,
    r.global_rownum,
    r.total_rows_window,
    r.bucket_answered_count
from ranked r
where (
    r.quality_score >= r.quality_median
    or (r.question_score >= 10 and r.viewcount >= 1000)
)
union all
select
    'No-Answers' as score_bucket,
    11 as quality_decile,
    q.question_id,
    q.title,
    coalesce(nullif(q.tags,''), '<untagged>') as tags,
    q.asker_id,
    coalesce(ru.displayname, '[user-deleted]') as asker_name,
    ru.reputation,
    ru.cohort_month,
    q.viewcount,
    q.question_score,
    q.upvotes,
    q.downvotes,
    q.favorites,
    q.bounty_total,
    coalesce(aa.answers_total,0),
    aa.best_answer_score,
    aa.first_answer_date,
    q.edits,
    q.comment_count,
    q.first_close_date,
    q.canonical_post_id,
    (select p.title from posts p where p.id = q.canonical_post_id) as canonical_title,
    -999 as quality_score,
    null as quality_median,
    999 as bucket_view_rank,
    999999 as global_rownum,
    0 as total_rows_window,
    0 as bucket_answered_count
from question_enriched q
left join answer_agg aa on aa.question_id = q.question_id
left join recent_users ru on ru.user_id = q.asker_id
where coalesce(aa.answers_total,0) = 0
order by score_bucket, quality_decile, bucket_view_rank, question_id;