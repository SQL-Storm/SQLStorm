-- {"query": "323.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2790} 
with params as (
    select
        now() - interval '365 days' as start_date,
        now() as end_date
),
active_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
        date_trunc('month', u.creationdate) as joined_month,
        count(distinct p.id) filter (where p.posttypeid in (1,2)) as total_posts,
        count(distinct c.id) as total_comments,
        count(distinct v.id) filter (where v.votetypeid in (2,3)) as total_cast_votes
    from users u
    left join posts p on p.owneruserid = u.id
    left join comments c on c.userid = u.id
    left join votes v on v.userid = u.id
    group by u.id, u.displayname, u.reputation, location_norm, joined_month
),
recent_q as (
    select
        p.id as question_id,
        p.owneruserid as asker_id,
        p.creationdate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        p.acceptedanswerid,
        array_length(string_to_array(substring(p.tags from 2 for length(p.tags)-2), '><'), 1) as tag_count
    from posts p
    join params on p.creationdate between params.start_date and params.end_date
    where p.posttypeid = 1
),
answers as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as answerer_id,
        a.creationdate as answer_date,
        a.score as answer_score
    from posts a
    where a.posttypeid = 2
),
first_answer as (
    select
        question_id,
        min(answer_date) as first_answer_date
    from answers
    group by question_id
),
answer_stats as (
    select
        a.question_id,
        count(*) as answer_count,
        max(a.answer_score) as max_answer_score,
        avg(a.answer_score::numeric) as avg_answer_score,
        sum(case when a.answer_score > 0 then 1 else 0 end) as positive_answers
    from answers a
    group by a.question_id
),
votes_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
    from votes v
    group by v.postid
),
close_events as (
    select
        ph.postid,
        min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_close_date,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopen_date,
        count(*) filter (where ph.posthistorytypeid = 10) as close_count,
        max(nullif(ph.comment, '')) filter (where ph.posthistorytypeid = 10) as last_close_reason_raw
    from posthistory ph
    group by ph.postid
),
dup_links as (
    select
        pl.postid as question_id,
        count(*) filter (where pl.linktypeid = 3) as duplicate_links
    from postlinks pl
    group by pl.postid
),
tag_breakout as (
    select
        rq.question_id,
        unnest(string_to_array(substring(rq.tags from 2 for length(rq.tags)-2), '><')) as tagname
    from recent_q rq
    where rq.tags is not null and rq.tags like '<%>'
),
top_tags as (
    select
        tb.tagname,
        count(*) as tag_uses,
        row_number() over (order by count(*) desc, tagname) as tag_rank
    from tag_breakout tb
    group by tb.tagname
),
asker_activity as (
    select
        rq.question_id,
        u.id as user_id,
        u.reputation,
        u.upvotes,
        u.downvotes,
        u.views,
        row_number() over (partition by rq.question_id order by u.reputation desc nulls last) as rep_rank_within_q
    from recent_q rq
    left join users u on u.id = rq.asker_id
),
string_metrics as (
    select
        rq.question_id,
        length(coalesce(rq.title, '')) as title_len,
        coalesce(cardinality(regexp_split_to_array(regexp_replace(coalesce(rq.title,''), '\s+', ' ', 'g'), ' ')), 0) as title_word_count,
        sum(length(word)) filter (where word <> '') as title_chars_no_space
    from (
        select
            question_id,
            title,
            unnest(regexp_split_to_array(coalesce(title,''), '\s+')) as word
        from recent_q
    ) rq
    group by rq.question_id, rq.title
),
question_windows as (
    select
        rq.*,
        vs.upvotes,
        vs.downvotes,
        vs.favorites,
        vs.bounty_total,
        coalesce(ans.answer_count, 0) as answer_count,
        coalesce(ans.max_answer_score, 0) as max_answer_score,
        coalesce(ans.avg_answer_score, 0) as avg_answer_score,
        fe.first_answer_date,
        ce.first_close_date,
        ce.last_reopen_date,
        ce.close_count,
        dl.duplicate_links,
        sm.title_len,
        sm.title_word_count,
        sm.title_chars_no_space,
        extract(epoch from (fe.first_answer_date - rq.creationdate)) as secs_to_first_answer,
        extract(epoch from (ce.first_close_date - rq.creationdate)) as secs_to_first_close
    from recent_q rq
    left join votes_agg vs on vs.postid = rq.question_id
    left join answer_stats ans on ans.question_id = rq.question_id
    left join first_answer fe on fe.question_id = rq.question_id
    left join close_events ce on ce.postid = rq.question_id
    left join dup_links dl on dl.question_id = rq.question_id
    left join string_metrics sm on sm.question_id = rq.question_id
),
bucketing as (
    select
        qw.*,
        case
            when coalesce(qw.viewcount,0) >= 100000 then 'Ultra'
            when coalesce(qw.viewcount,0) >= 10000 then 'High'
            when coalesce(qw.viewcount,0) >= 1000 then 'Medium'
            when coalesce(qw.viewcount,0) > 0 then 'Low'
            else 'None'
        end as view_bucket,
        case
            when coalesce(qw.score,0) >= 50 then 'S-Tier'
            when coalesce(qw.score,0) >= 10 then 'A'
            when coalesce(qw.score,0) >= 1 then 'B'
            when coalesce(qw.score,0) = 0 then 'C'
            else 'D'
        end as score_grade,
        ntile(10) over (order by coalesce(qw.viewcount,0) desc nulls last) as view_ntile_10,
        row_number() over (partition by date_trunc('day', qw.creationdate) order by coalesce(qw.viewcount,0) desc nulls last, qw.score desc nulls last, qw.id) as daily_rank
    from question_windows qw
),
asker_quality as (
    select
        b.question_id,
        case
            when aa.reputation >= 100000 then 'Legend'
            when aa.reputation >= 10000 then 'Veteran'
            when aa.reputation >= 1000 then 'Experienced'
            when aa.reputation >= 100 then 'Novice'
            else 'Newbie'
        end as asker_band,
        aa.reputation as asker_rep,
        aa.rep_rank_within_q
    from bucketing b
    left join asker_activity aa on aa.question_id = b.question_id
),
best_answerer as (
    select
        a.question_id,
        a.answerer_id,
        a.answer_score,
        row_number() over (partition by a.question_id order by a.answer_score desc nulls last, a.creationdate asc) as rn
    from answers a
),
final as (
    select
        b.question_id,
        coalesce(u.displayname, '[unknown]') as asker_name,
        coalesce(u.location, 'Unknown') as asker_location,
        aq.asker_band,
        aq.asker_rep,
        b.creationdate,
        b.title,
        b.tag_count,
        b.viewcount,
        b.score,
        b.view_bucket,
        b.score_grade,
        b.view_ntile_10,
        b.daily_rank,
        b.answer_count,
        b.max_answer_score,
        b.avg_answer_score,
        b.upvotes,
        b.downvotes,
        b.favorites,
        b.bounty_total,
        b.first_answer_date,
        b.first_close_date,
        b.last_reopen_date,
        b.close_count,
        b.duplicate_links,
        coalesce(b.secs_to_first_answer, -1) as secs_to_first_answer,
        coalesce(b.secs_to_first_close, -1) as secs_to_first_close,
        b.title_len,
        b.title_word_count,
        b.title_chars_no_space,
        case when b.acceptedanswerid is not null then 1 else 0 end as has_accepted_answer,
        case when b.first_close_date is not null and b.last_reopen_date is null then 'Closed'
             when b.first_close_date is not null and b.last_reopen_date is not null and b.last_reopen_date > b.first_close_date then 'Reopened'
             else 'Open' end as close_state,
        bt.tagname as top_global_tag_if_present,
        case when bt.tag_rank <= 10 then 'Top10Tag' else 'OtherTag' end as top_tag_bucket,
        ba.answerer_id as top_answerer_id,
        ba.answer_score as top_answer_score
    from bucketing b
    left join users u on u.id = b.asker_id
    left join asker_quality aq on aq.question_id = b.question_id
    left join best_answerer ba on ba.question_id = b.question_id and ba.rn = 1
    left join lateral (
        select tt.tagname, tt.tag_rank
        from top_tags tt
        join tag_breakout tb on tb.tagname = tt.tagname and tb.question_id = b.question_id
        order by tt.tag_rank
        limit 1
    ) bt on true
),
rollup_by_day as (
    select
        date_trunc('day', f.creationdate) as day,
        count(*) as questions,
        sum(f.answer_count) as total_answers,
        avg(nullif(f.viewcount,0)::numeric) as avg_views,
        percentile_cont(0.5) within group (order by f.viewcount) as p50_views,
        sum(case when f.has_accepted_answer = 1 then 1 else 0 end) as accepted_count,
        sum(case when f.close_state = 'Closed' then 1 else 0 end) as closed_count
    from final f
    group by 1
),
ranked as (
    select
        f.*,
        row_number() over (order by coalesce(f.viewcount,0) desc, f.score desc, f.question_id) as global_rank_by_views_score,
        dense_rank() over (partition by f.top_tag_bucket order by coalesce(f.bounty_total,0) desc) as tag_bucket_bounty_rank
    from final f
)
select
    r.*,
    rd.questions as day_questions,
    rd.total_answers as day_total_answers,
    rd.avg_views as day_avg_views,
    rd.p50_views as day_p50_views,
    rd.accepted_count as day_accepted,
    rd.closed_count as day_closed
from ranked r
left join rollup_by_day rd on rd.day = date_trunc('day', r.creationdate)
where
    (
        r.view_bucket in ('Ultra','High')
        or (r.score_grade in ('S-Tier','A') and coalesce(r.answer_count,0) >= 2)
        or (r.top_tag_bucket = 'Top10Tag' and coalesce(r.viewcount,0) >= 500)
        or (r.close_state <> 'Open' and coalesce(r.secs_to_first_close,-1) > 0)
    )
    and coalesce(r.title_word_count,0) between 3 and 30
    and coalesce(r.title_len,0) <= 300
order by
    r.global_rank_by_views_score,
    r.tag_bucket_bounty_rank
limit 500;