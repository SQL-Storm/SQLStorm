-- {"query": "720.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2989} 
with recursive tag_tokens as (
    select
        p.Id as PostId,
        lower(trim(both '<>' from regexp_split_to_table(coalesce(p.Tags, ''), '><'))) as Tag
    from Posts p
    where p.PostTypeId = 1
),
recent_activity as (
    select
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.CommentCount,
        p.CreationDate,
        p.LastActivityDate,
        p.ClosedDate,
        p.Title,
        p.Tags
    from Posts p
    where p.CreationDate >= (select max(CreationDate) - interval '365 days' from Posts)
),
user_stats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate as UserCreationDate,
        u.Location,
        u.UpVotes,
        u.DownVotes,
        u.Views as ProfileViews,
        coalesce(sum(case when b.Class = 1 then 1 end),0) as GoldBadges,
        coalesce(sum(case when b.Class = 2 then 1 end),0) as SilverBadges,
        coalesce(sum(case when b.Class = 3 then 1 end),0) as BronzeBadges,
        count(b.Id) as TotalBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.UpVotes, u.DownVotes, u.Views
),
vote_agg as (
    select
        v.PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
        sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyTotal,
        max(case when v.VoteTypeId = 8 then v.CreationDate end) as LastBountyStart
    from Votes v
    group by v.PostId
),
comment_agg as (
    select
        c.PostId,
        count(*) as CommentCount,
        max(c.CreationDate) as LastCommentDate,
        sum(case when c.Score >= 5 then 1 else 0 end) as HighScoreComments
    from Comments c
    group by c.PostId
),
duplicate_links as (
    select
        pl.PostId,
        count(*) filter (where pl.LinkTypeId = 3) as DuplicateCount,
        count(*) filter (where pl.LinkTypeId = 1) as LinkedCount,
        max(pl.CreationDate) as LastLinkDate
    from PostLinks pl
    group by pl.PostId
),
edits_cte as (
    select
        ph.PostId,
        count(*) filter (where ph.PostHistoryTypeId in (4,5,6,7,8,9,24)) as EditEvents,
        count(*) filter (where ph.PostHistoryTypeId in (10)) as CloseVotes,
        count(*) filter (where ph.PostHistoryTypeId in (11)) as ReopenVotes,
        count(*) filter (where ph.PostHistoryTypeId in (12)) as DeleteVotes,
        max(ph.CreationDate) as LastEditDate
    from PostHistory ph
    group by ph.PostId
),
question_basics as (
    select
        q.Id,
        q.OwnerUserId,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        q.CommentCount,
        q.CreationDate,
        q.LastActivityDate,
        q.ClosedDate,
        q.Title,
        q.Tags,
        (q.Score::numeric / nullif(greatest(extract(epoch from age(coalesce(q.LastActivityDate, q.CreationDate), q.CreationDate)) / 3600.0, 1), 0)) as ScorePerHour
    from recent_activity q
    where q.PostTypeId = 1 or q.PostTypeId is null
),
answer_stats as (
    select
        a.ParentId as QuestionId,
        count(*) as Answers,
        sum(case when a.Score > 0 then 1 else 0 end) as PosAns,
        max(a.Score) as MaxAnswerScore,
        max(a.CreationDate) as LastAnswerDate,
        sum(case when a.OwnerUserId is null then 1 else 0 end) as AnonymousAnswers
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),
tag_density as (
    select
        t.PostId,
        count(*) as TagCount,
        string_agg(distinct tag_tokens.Tag, ', ' order by tag_tokens.Tag) as TagList,
        bool_or(tag_tokens.Tag = 'sql') as HasSQL,
        sum(case when tag_tokens.Tag in ('sql','postgresql','mysql','tsql','oracle') then 1 else 0 end) as RdbmsTagHits
    from tag_tokens t
    group by t.PostId
),
ranked_questions as (
    select
        qb.Id,
        qb.OwnerUserId,
        qb.Title,
        qb.Tags,
        qb.Score,
        qb.ViewCount,
        qb.AnswerCount,
        qb.FavoriteCount,
        qb.CommentCount,
        qb.CreationDate,
        qb.LastActivityDate,
        qb.ClosedDate,
        qb.ScorePerHour,
        coalesce(va.UpVotes,0) as UpVotes,
        coalesce(va.DownVotes,0) as DownVotes,
        coalesce(va.Favorites,0) as VoteFavorites,
        coalesce(va.BountyTotal,0) as BountyTotal,
        va.LastBountyStart,
        coalesce(ca.CommentCount,0) as AggCommentCount,
        ca.LastCommentDate,
        coalesce(ca.HighScoreComments,0) as HighScoreComments,
        coalesce(dl.DuplicateCount,0) as DuplicateCount,
        coalesce(dl.LinkedCount,0) as LinkedCount,
        dl.LastLinkDate,
        coalesce(ec.EditEvents,0) as EditEvents,
        coalesce(ec.CloseVotes,0) as CloseVotes,
        coalesce(ec.ReopenVotes,0) as ReopenVotes,
        coalesce(ec.DeleteVotes,0) as DeleteVotes,
        ec.LastEditDate,
        coalesce(ans.Answers,0) as Answers,
        coalesce(ans.PosAns,0) as PositiveAnswers,
        ans.MaxAnswerScore,
        ans.LastAnswerDate,
        coalesce(td.TagCount,0) as TagCount,
        td.TagList,
        td.HasSQL,
        td.RdbmsTagHits,
        dense_rank() over (order by qb.Score desc nulls last, qb.ViewCount desc nulls last) as ScoreRank,
        row_number() over (order by coalesce(va.UpVotes,0) - coalesce(va.DownVotes,0) desc, qb.Id) as NetVoteRowNum,
        percentile_disc(0.9) within group (order by qb.ViewCount) over () as P90Views
    from question_basics qb
    left join vote_agg va on va.PostId = qb.Id
    left join comment_agg ca on ca.PostId = qb.Id
    left join duplicate_links dl on dl.PostId = qb.Id
    left join edits_cte ec on ec.PostId = qb.Id
    left join answer_stats ans on ans.QuestionId = qb.Id
    left join tag_density td on td.PostId = qb.Id
),
user_quality as (
    select
        rs.Id as PostId,
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.Location,
        us.UpVotes as UserUpVotes,
        us.DownVotes as UserDownVotes,
        us.ProfileViews,
        us.TotalBadges,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        case
            when us.Reputation >= 100000 then 'legend'
            when us.Reputation >= 25000 then 'elite'
            when us.Reputation >= 10000 then 'pro'
            when us.Reputation >= 3000 then 'intermediate'
            else 'newbie'
        end as RepTier
    from ranked_questions rs
    left join user_stats us on us.UserId = rs.OwnerUserId
),
null_sentinel as (
    select
        rs.Id as PostId,
        case when rs.ClosedDate is null then 0 else 1 end as IsClosed,
        case when rs.TagCount = 0 then null else rs.TagCount end as NullableTagCount,
        coalesce(rs.ScorePerHour, 0.0) as ScorePerHourNZ,
        coalesce(rs.TagList, '(none)') as TagListNZ
    from ranked_questions rs
),
banded as (
    select
        rs.*,
        uq.DisplayName,
        uq.RepTier,
        ns.IsClosed,
        ns.NullableTagCount,
        ns.ScorePerHourNZ,
        ns.TagListNZ,
        width_bucket(coalesce(rs.ViewCount,0), 0, greatest(rs.P90Views, 1), 10) as ViewBucket,
        case when rs.HasSQL then 1 else 0 end as SQLFlag
    from ranked_questions rs
    left join user_quality uq on uq.PostId = rs.Id
    left join null_sentinel ns on ns.PostId = rs.Id
),
top_per_tag as (
    select
        bt.Id,
        bt.Title,
        bt.Score,
        bt.ViewCount,
        bt.TagList,
        bt.TagCount,
        tt.Tag,
        row_number() over (partition by tt.Tag order by bt.Score desc, bt.ViewCount desc, bt.Id) as rn_by_tag
    from banded bt
    join tag_tokens tt on tt.PostId = bt.Id
),
closed_reason_extract as (
    select
        ph.PostId,
        max(ph.CreationDate) as LastCloseEvent,
        max(
            case
                when ph.PostHistoryTypeId = 10 then
                    nullif(regexp_replace(coalesce(ph.Comment,''), '[^0-9]+', '', 'g'), '')::int
            end
        ) as LastCloseReasonId
    from PostHistory ph
    where ph.PostHistoryTypeId = 10
    group by ph.PostId
),
final_scores as (
    select
        b.*,
        coalesce(cr.LastCloseReasonId, 0) as LastCloseReasonId,
        coalesce(cr.LastCloseEvent, timestamp 'epoch') as LastCloseEvent,
        (coalesce(b.UpVotes,0) - coalesce(b.DownVotes,0)) as NetVotes,
        (coalesce(b.Score,0) + coalesce(b.UpVotes,0) - coalesce(b.DownVotes,0)
            + least(coalesce(b.BountyTotal,0)/100, 50)
            + coalesce(b.PositiveAnswers,0)
            + case when b.HasSQL then 5 else 0 end
            - coalesce(b.DuplicateCount,0)
            - case when b.IsClosed = 1 then 3 else 0 end
        ) as CompositeScore
    from banded b
    left join closed_reason_extract cr on cr.PostId = b.Id
)
select
    fs.Id as QuestionId,
    coalesce(fs.Title, '(untitled)') as Title,
    fs.DisplayName as Owner,
    fs.RepTier,
    fs.Score,
    fs.NetVotes,
    fs.ViewCount,
    fs.Answers,
    fs.MaxAnswerScore,
    fs.VoteFavorites as Favorites,
    fs.BountyTotal,
    fs.EditEvents,
    fs.DuplicateCount,
    fs.CloseVotes,
    fs.ReopenVotes,
    fs.DeleteVotes,
    fs.IsClosed,
    fs.LastCloseReasonId,
    fs.TagListNZ as Tags,
    fs.TagCount,
    fs.HasSQL,
    fs.RdbmsTagHits,
    fs.ScorePerHourNZ as ScorePerHour,
    fs.ViewBucket,
    fs.HighScoreComments,
    fs.LastAnswerDate,
    fs.LastCommentDate,
    fs.LastEditDate,
    fs.LastLinkDate,
    fs.LastBountyStart,
    fs.ScoreRank,
    fs.NetVoteRowNum,
    fs.CompositeScore,
    array(
        select tp.Tag
        from top_per_tag tp
        where tp.Id = fs.Id and tp.rn_by_tag <= 1
        order by tp.Tag
    ) as RepresentativeTag,
    case
        when fs.CompositeScore >= percentile_cont(0.95) within group (order by fs.CompositeScore) over () then 'top-5%'
        when fs.CompositeScore >= percentile_cont(0.75) within group (order by fs.CompositeScore) over () then 'top-25%'
        else 'normal'
    end as ScoreBand
from final_scores fs
where
    -- elaborate predicate combining string, numeric and null logic
    (
        fs.HasSQL = true
        or (fs.TagCount >= 3 and fs.RdbmsTagHits >= 2)
        or (fs.Score > 50 and coalesce(fs.ViewCount,0) > 10000)
        or (fs.CompositeScore > 100 and (fs.ClosedDate is null or fs.ReopenVotes > fs.CloseVotes))
    )
    and not (fs.DuplicateCount > 5 and fs.Score < 0)
    and (fs.LastCloseReasonId is null or fs.LastCloseReasonId not in (101))
    and (fs.TagListNZ ilike any (array['%sql%','%database%','%query%']))
order by
    fs.CompositeScore desc,
    fs.Score desc nulls last,
    fs.ViewCount desc nulls last,
    fs.Id
limit 200;