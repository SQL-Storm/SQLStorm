-- {"query": "354.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2722}
with recent_questions as (
    select
        q.Id as QuestionId,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.OwnerUserId,
        q.AcceptedAnswerId,
        coalesce(nullif(trim(q.Title), ''), '(untitled)') as Title,
        string_to_array(substring(q.Tags from 2 for greatest(char_length(q.Tags)-2,0)), '><') as TagArray
    from Posts q
    where q.PostTypeId = 1
      and q.CreationDate >= (select max(CreationDate) - interval '365 days' from Posts where PostTypeId = 1)
),
tag_expanded as (
    select
        rq.QuestionId,
        lower(trim(tg)) as tag
    from recent_questions rq,
    lateral (
      select unnest(rq.TagArray) as tg
    ) u
),
tag_stats as (
    select
        te.QuestionId,
        count(*) filter (where te.tag is not null) as tag_count,
        min(te.tag) as first_tag_alpha,
        max(te.tag) as last_tag_alpha
    from tag_expanded te
    group by te.QuestionId
),
question_activity as (
    select
        q.Id as QuestionId,
        coalesce(q.AnswerCount, 0) as AnswerCount,
        coalesce(q.CommentCount, 0) as CommentCount,
        q.LastActivityDate,
        q.ClosedDate,
        case when q.ClosedDate is not null then 1 else 0 end as IsClosed
    from Posts q
    where q.PostTypeId = 1
),
answers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        row_number() over (partition by a.ParentId order by a.Score desc nulls last, a.CreationDate asc) as rn_score,
        row_number() over (partition by a.ParentId order by a.CreationDate asc) as rn_time
    from Posts a
    where a.PostTypeId = 2
),
accepted_vs_best as (
    select
        rq.QuestionId,
        rq.AcceptedAnswerId,
        max(case when an.rn_score = 1 then an.AnswerId end) as TopScoreAnswerId,
        max(case when an.rn_time = 1 then an.AnswerId end) as FirstAnswerId,
        max(case when an.rn_score = 1 then an.Score end) as TopScore,
        max(case when an.AnswerId = rq.AcceptedAnswerId then an.Score end) as AcceptedScore
    from recent_questions rq
    left join answers an on an.QuestionId = rq.QuestionId
    group by rq.QuestionId, rq.AcceptedAnswerId
),
votes_rollup as (
    select
        v.PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 10 then 1 else 0 end) as Deletions,
        sum(case when v.VoteTypeId = 11 then 1 else 0 end) as Undeletions
    from Votes v
    group by v.PostId
),
comment_agg as (
    select
        c.PostId,
        count(*) as CommentCount,
        max(c.Score) as MaxCommentScore,
        avg(c.Score) filter (where c.Score is not null) as AvgCommentScore,
        min(c.CreationDate) as FirstCommentAt,
        max(c.CreationDate) as LastCommentAt
    from Comments c
    group by c.PostId
),
user_metrics as (
    select
        u.Id as UserId,
        u.Reputation,
        coalesce(u.UpVotes,0) - coalesce(u.DownVotes,0) as NetVotes,
        cast(date_part('year', age(timestamp '2024-10-01 12:34:56', u.CreationDate)) as int) as AccountAgeYears,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as LastBadgeAt
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.Reputation, u.UpVotes, u.DownVotes, u.CreationDate
),
closure_reasons as (
    select
        ph.PostId,
        max(ph.CreationDate) as LastCloseEventAt,
        max(case when ph.PostHistoryTypeId = 10 then ph.Comment end) as LastCloseReasonId,
        max(case when ph.PostHistoryTypeId = 10 then ph.Text end) as CloseVotesJson
    from PostHistory ph
    where ph.PostHistoryTypeId in (10,11)
    group by ph.PostId
),
duplicates as (
    select
        pl.PostId as QuestionId,
        count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinks,
        count(*) filter (where pl.LinkTypeId = 1) as LinkedLinks,
        (select string_agg(r.RelatedPostId_str, ',') from (
            select distinct cast(pl2.RelatedPostId as varchar) as RelatedPostId_str
            from PostLinks pl2
            where pl2.PostId = pl.PostId
            order by cast(pl2.RelatedPostId as varchar)
        ) r) as RelatedIds
    from PostLinks pl
    group by pl.PostId
),
tag_popularity as (
    select
        lower(t.TagName) as tag,
        t.Count,
        dense_rank() over (order by t.Count desc) as tag_rank
    from Tags t
),
question_tag_rank as (
    select
        te.QuestionId,
        min(tp.tag_rank) as best_tag_rank,
        max(tp.tag_rank) as worst_tag_rank
    from tag_expanded te
    left join tag_popularity tp on tp.tag = te.tag
    group by te.QuestionId
),
question_quality as (
    select
        rq.QuestionId,
        rq.Title,
        rq.CreationDate,
        rq.Score,
        rq.ViewCount,
        ts.tag_count,
        qa.AnswerCount,
        qa.CommentCount,
        qa.LastActivityDate,
        qa.IsClosed,
        avr.TopScore,
        avr.AcceptedScore,
        coalesce(vr.UpVotes,0) as UpVotes,
        coalesce(vr.DownVotes,0) as DownVotes,
        coalesce(ca.CommentCount,0) as TotalComments,
        coalesce(ca.AvgCommentScore,0) as AvgCommentScore,
        coalesce(ca.MaxCommentScore,0) as MaxCommentScore,
        coalesce(dr.DuplicateLinks,0) as DuplicateLinks,
        coalesce(dr.LinkedLinks,0) as LinkedLinks,
        qtr.best_tag_rank,
        qtr.worst_tag_rank,
        char_length(regexp_replace(coalesce(rq.Title,''), '\s+', '', 'g')) as TitleCharNoSpace,
        case when rq.Title ~* '\b(how|why|what|where|when)\b' then 1 else 0 end as HasInterrogativeWord
    from recent_questions rq
    left join tag_stats ts on ts.QuestionId = rq.QuestionId
    left join question_activity qa on qa.QuestionId = rq.QuestionId
    left join accepted_vs_best avr on avr.QuestionId = rq.QuestionId
    left join votes_rollup vr on vr.PostId = rq.QuestionId
    left join comment_agg ca on ca.PostId = rq.QuestionId
    left join duplicates dr on dr.QuestionId = rq.QuestionId
    left join question_tag_rank qtr on qtr.QuestionId = rq.QuestionId
),
ranked as (
    select
        qq.*,
        coalesce(1.0 * qq.Score, 0)
        + coalesce(0.1 * qq.ViewCount, 0)
        + coalesce(2.0 * qq.UpVotes - 3.0 * qq.DownVotes, 0)
        + coalesce(1.5 * qq.TopScore, 0)
        + coalesce(case when qq.AcceptedScore is not null then 5.0 else 0 end, 0)
        - coalesce(2.5 * qq.DuplicateLinks, 0)
        - coalesce(1.0 * qq.IsClosed, 0)
        + coalesce(0.2 * qq.tag_count, 0)
        - coalesce(0.05 * least(greatest(qq.TitleCharNoSpace - 60, 0), 200), 0)
        + coalesce(0.5 * qq.HasInterrogativeWord, 0)
        as QualityScore,
        row_number() over (order by
            coalesce(1.0 * qq.Score,0) + coalesce(0.1 * qq.ViewCount,0) + coalesce(2.0 * qq.UpVotes - 3.0 * qq.DownVotes,0)
            + coalesce(1.5 * qq.TopScore,0) + coalesce(case when qq.AcceptedScore is not null then 5.0 else 0 end,0)
            - coalesce(2.5 * qq.DuplicateLinks,0) - coalesce(1.0 * qq.IsClosed,0)
            + coalesce(0.2 * qq.tag_count,0)
            - coalesce(0.05 * least(greatest(qq.TitleCharNoSpace - 60, 0), 200), 0)
            + coalesce(0.5 * qq.HasInterrogativeWord,0)
            desc, qq.CreationDate desc, qq.QuestionId) as rn
    from question_quality qq
),
author_join as (
    select
        rq.QuestionId,
        u.Id as AuthorId,
        coalesce(u.DisplayName, '(unknown)') as AuthorName,
        um.Reputation,
        um.NetVotes,
        um.AccountAgeYears,
        um.GoldBadges,
        um.SilverBadges,
        um.BronzeBadges,
        um.LastBadgeAt
    from recent_questions rq
    left join Users u on u.Id = rq.OwnerUserId
    left join user_metrics um on um.UserId = u.Id
),
final_projection as (
    select
        r.QuestionId,
        r.Title,
        r.CreationDate,
        r.Score,
        r.ViewCount,
        r.tag_count,
        r.AnswerCount,
        r.CommentCount,
        r.LastActivityDate,
        r.IsClosed,
        r.TopScore,
        r.AcceptedScore,
        r.UpVotes,
        r.DownVotes,
        r.TotalComments,
        r.AvgCommentScore,
        r.MaxCommentScore,
        r.DuplicateLinks,
        r.LinkedLinks,
        r.best_tag_rank,
        r.worst_tag_rank,
        r.QualityScore,
        aj.AuthorId,
        aj.AuthorName,
        aj.Reputation,
        aj.NetVotes,
        aj.AccountAgeYears,
        aj.GoldBadges,
        aj.SilverBadges,
        aj.BronzeBadges,
        aj.LastBadgeAt,
        r.rn
    from ranked r
    left join author_join aj on aj.QuestionId = r.QuestionId
),
dedup as (
    select *
    from (
      select
        fp.*,
        row_number() over (partition by fp.QuestionId order by fp.rn) as _dedup_rn
      from final_projection fp
    ) t
    where t._dedup_rn = 1
)
select
    d.QuestionId,
    d.Title,
    d.CreationDate,
    d.Score,
    d.ViewCount,
    d.AnswerCount,
    d.CommentCount,
    d.LastActivityDate,
    d.IsClosed,
    d.QualityScore,
    coalesce(crt.Name, 'Unknown') as LastCloseReasonName,
    d.AuthorName,
    d.Reputation,
    d.AccountAgeYears,
    d.GoldBadges,
    d.SilverBadges,
    d.BronzeBadges,
    d.UpVotes,
    d.DownVotes,
    d.TotalComments,
    d.AvgCommentScore,
    d.MaxCommentScore,
    d.DuplicateLinks,
    d.LinkedLinks,
    d.best_tag_rank,
    d.worst_tag_rank
from dedup d
left join closure_reasons cr on cr.PostId = d.QuestionId
left join CloseReasonTypes crt on crt.Id = cast(nullif(cr.LastCloseReasonId, '') as smallint)
where coalesce(d.QualityScore, 0) > (
    select avg(coalesce(QualityScore,0)) from ranked
)
and (
    d.AcceptedScore is not null
    or d.TopScore >= 2
    or (d.AnswerCount >= 3 and d.Score >= 1)
)
order by d.QualityScore desc, d.CreationDate desc
limit 200;