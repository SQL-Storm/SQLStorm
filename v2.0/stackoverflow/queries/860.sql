-- {"query": "860.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2633}
with recent_questions as (
    select
        p.Id as QuestionId,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        case when p.ClosedDate is null then 0 else 1 end as IsClosed
    from Posts p
    where p.PostTypeId = 1
      and p.CreationDate >= (select max(CreationDate) - interval '365 days' from Posts)
),
answers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswerOwnerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate
    from Posts a
    where a.PostTypeId = 2
),
first_answer as (
    select *
    from (
        select
            QuestionId,
            AnswerId,
            AnswerOwnerId,
            AnswerScore,
            AnswerCreationDate,
            row_number() over (partition by QuestionId order by AnswerCreationDate asc, AnswerId asc) as rn
        from answers
    ) t
    where rn = 1
),
votes_agg as (
    select
        v.PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
        sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount, 0) else 0 end) as BountyStarted,
        sum(case when v.VoteTypeId = 9 then coalesce(v.BountyAmount, 0) else 0 end) as BountyAwarded,
        count(*) as TotalVotes
    from Votes v
    where v.CreationDate >= (select max(CreationDate) - interval '365 days' from Votes)
    group by v.PostId
),
dupe_links as (
    select
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId,
        min(pl.CreationDate) as FirstDupLinkDate
    from PostLinks pl
    where pl.LinkTypeId = 3
    group by pl.PostId, pl.RelatedPostId
),
closed_reasons as (
    select
        ph.PostId,
        max(ph.CreationDate) as ClosedDate,
        max(case
            when ph.PostHistoryTypeId = 10 then
                case
                    when ph.Comment ~ '^[0-9]+$' then ph.Comment
                    else null
                end
            else null
        end) as CloseReasonIdText
    from PostHistory ph
    where ph.PostHistoryTypeId in (10, 11)
    group by ph.PostId
),
tags_expanded as (
    select
        q.QuestionId,
        unnest(string_to_array(substring(q.Tags from 2 for char_length(q.Tags)-2), '><')) as tag
    from recent_questions q
    where q.Tags is not null
),
tag_stats as (
    select
        te.QuestionId,
        count(*) as TagCount,
        sum(case when lower(te.tag) in ('sql','postgresql','mysql','sqlite','tsql','plpgsql') then 1 else 0 end) as SqlTagHits,
        string_agg(te.tag, '|' order by te.tag) as TagListPipe
    from tags_expanded te
    group by te.QuestionId
),
user_activity as (
    select
        u.Id as UserId,
        u.Reputation,
        u.CreationDate,
        u.UpVotes as ProfileUpVotes,
        u.DownVotes as ProfileDownVotes,
        u.Views as ProfileViews,
        coalesce(b.BadgeScore, 0) as BadgeScore
    from Users u
    left join (
        select
            b.UserId,
            sum(case b.Class when 1 then 100 when 2 then 10 when 3 then 1 else 0 end) as BadgeScore
        from Badges b
        group by b.UserId
    ) b on b.UserId = u.Id
),
comment_activity as (
    select
        c.PostId,
        count(*) as CommentCount,
        max(c.CreationDate) as LastCommentDate,
        sum(case when c.Score >= 5 then 1 else 0 end) as HighScoreComments
    from Comments c
    group by c.PostId
),
question_metrics as (
    select
        q.QuestionId,
        q.CreationDate,
        q.OwnerUserId,
        q.Score as QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.IsClosed,
        fa.AnswerId as FirstAnswerId,
        fa.AnswerOwnerId,
        fa.AnswerScore,
        fa.AnswerCreationDate,
        vt.UpVotes as VoteUps,
        vt.DownVotes as VoteDowns,
        vt.Favorites as VoteFavorites,
        vt.BountyStarted,
        vt.BountyAwarded,
        vt.TotalVotes,
        dr.OriginalQuestionId,
        dr.FirstDupLinkDate,
        cr.ClosedDate as ClosedAt,
        cr.CloseReasonIdText,
        ts.TagCount,
        ts.SqlTagHits,
        ts.TagListPipe,
        ca.CommentCount,
        ca.LastCommentDate,
        ca.HighScoreComments
    from recent_questions q
    left join first_answer fa on fa.QuestionId = q.QuestionId
    left join votes_agg vt on vt.PostId = q.QuestionId
    left join dupe_links dr on dr.DuplicateQuestionId = q.QuestionId
    left join closed_reasons cr on cr.PostId = q.QuestionId
    left join tag_stats ts on ts.QuestionId = q.QuestionId
    left join comment_activity ca on ca.PostId = q.QuestionId
),
ranked as (
    select
        qm.QuestionId,
        qm.CreationDate,
        qm.OwnerUserId,
        qm.QuestionScore,
        qm.ViewCount,
        qm.AnswerCount,
        qm.IsClosed,
        qm.FirstAnswerId,
        qm.AnswerOwnerId,
        qm.AnswerScore,
        qm.AnswerCreationDate,
        qm.VoteUps,
        qm.VoteDowns,
        qm.VoteFavorites,
        qm.BountyStarted,
        qm.BountyAwarded,
        qm.TotalVotes,
        qm.OriginalQuestionId,
        qm.FirstDupLinkDate,
        qm.ClosedAt,
        qm.CloseReasonIdText,
        qm.TagCount,
        qm.SqlTagHits,
        qm.TagListPipe,
        qm.CommentCount,
        qm.LastCommentDate,
        qm.HighScoreComments,
        ua.Reputation as OwnerReputation,
        ua.BadgeScore as OwnerBadgeScore,
        rank() over (order by coalesce(qm.ViewCount,0) desc) as r_view,
        dense_rank() over (order by coalesce(qm.TotalVotes,0) desc) as r_votes,
        row_number() over (partition by (qm.AnswerOwnerId is not null) order by coalesce(qm.AnswerScore, -2147483648) desc NULLS LAST, qm.QuestionId) as r_first_answer_score,
        ntile(10) over (order by coalesce(qm.QuestionScore,0) desc) as decile_score,
        sum(coalesce(qm.ViewCount,0)) over (order by qm.CreationDate rows between unbounded preceding and current row) as running_views,
        avg(coalesce(qm.QuestionScore,0)) over (partition by (qm.SqlTagHits > 0) order by qm.CreationDate rows between 99 preceding and current row) as rolling_avg_score_100
    from question_metrics qm
    left join user_activity ua on ua.UserId = qm.OwnerUserId
),
outliers as (
    select
        QuestionId,
        case
            when coalesce(ViewCount,0) > 0 and coalesce(TotalVotes,0) > 0
                 and (coalesce(ViewCount,0) / nullif(coalesce(TotalVotes,0),0)) > (
                        select 3 * avg(coalesce(ViewCount,0) / nullif(nullif(coalesce(TotalVotes,0),0),0))
                        from question_metrics
                  )
            then 1 else 0 end as IsViewPerVoteOutlier
    from question_metrics
),
final as (
    select
        r.QuestionId,
        r.CreationDate,
        r.OwnerUserId,
        r.OwnerReputation,
        r.OwnerBadgeScore,
        r.QuestionScore,
        r.ViewCount,
        r.AnswerCount,
        r.IsClosed,
        r.FirstAnswerId,
        r.AnswerOwnerId,
        r.AnswerScore,
        r.AnswerCreationDate,
        r.VoteUps,
        r.VoteDowns,
        r.VoteFavorites,
        r.BountyStarted,
        r.BountyAwarded,
        r.TotalVotes,
        r.OriginalQuestionId,
        r.FirstDupLinkDate,
        r.ClosedAt,
        r.CloseReasonIdText,
        r.TagCount,
        r.SqlTagHits,
        r.TagListPipe,
        r.CommentCount,
        r.LastCommentDate,
        r.HighScoreComments,
        r.r_view,
        r.r_votes,
        r.r_first_answer_score,
        r.decile_score,
        r.running_views,
        r.rolling_avg_score_100,
        o.IsViewPerVoteOutlier,
        case
            when r.SqlTagHits > 0 then 'SQL-Related'
            when r.TagCount is null then 'No Tags'
            when r.TagCount = 0 then 'Zero Tags'
            when r.TagCount >= 5 then 'Many Tags'
            else 'Some Tags'
        end as TagCategory,
        case
            when r.IsClosed = 1 and r.ClosedAt is not null then cast(extract(epoch from (r.ClosedAt - r.CreationDate)) as bigint)
            when r.IsClosed = 0 then null
            else null
        end as SecondsUntilClosed,
        case
            when r.TotalVotes is null or r.TotalVotes = 0 then null
            else round(cast((coalesce(r.VoteUps,0) - coalesce(r.VoteDowns,0)) as numeric) / r.TotalVotes, 4)
        end as NetVoteRatio,
        case
            when r.ViewCount is null or r.ViewCount = 0 then null
            else round(cast(coalesce(r.VoteFavorites, 0) as numeric) / r.ViewCount, 6)
        end as FavoriteViewRate,
        case
            when r.AnswerCreationDate is null then null
            else cast(extract(epoch from (r.AnswerCreationDate - r.CreationDate)) as bigint)
        end as SecondsToFirstAnswer,
        case
            when r.TagListPipe is null then null
            else regexp_replace(lower(r.TagListPipe), '(?:(^|[|]))(c\\+\\+|c#)($|[|])', '\\1cpp\\3', 'g')
        end as NormalizedTagList,
        coalesce(r.TagListPipe, '') || '|' || coalesce(cast(r.OwnerUserId as varchar), '') as TagUserConcat
    from ranked r
    left join outliers o on o.QuestionId = r.QuestionId
)
select
    f.*,
    case
        when f.AnswerOwnerId is null then null
        else (
            select
                sum(case when p2.Score >= 10 then 1 else 0 end)
            from Posts p2
            where p2.PostTypeId = 2
              and p2.OwnerUserId = f.AnswerOwnerId
              and p2.CreationDate >= f.CreationDate - interval '365 days'
        )
    end as AnswererHighScoreAnswersLastYear,
    case
        when f.OriginalQuestionId is null then null
        else (
            select
                count(distinct pl2.PostId)
            from PostLinks pl2
            where pl2.LinkTypeId = 3
              and pl2.RelatedPostId = f.OriginalQuestionId
        )
    end as DuplicateGroupSize,
    case
        when f.OwnerUserId is null then null
        else (
            select
                max(case when u2.CreationDate <= f.CreationDate then u2.Reputation else null end)
            from Users u2
            where u2.Id = f.OwnerUserId
        )
    end as OwnerRepAtQuestionTime
from final f
where (
        f.SqlTagHits > 0
        or (f.NetVoteRatio is not null and f.NetVoteRatio < 0)
        or (f.AnswerCount = 0 and f.ViewCount > 1000)
      )
  and coalesce(f.ViewCount,0) >= all (
        select coalesce(ViewCount,0)
        from final f2
        where f2.OwnerUserId = f.OwnerUserId
      )
order by
    f.r_view asc,
    f.QuestionId asc
limit 500;