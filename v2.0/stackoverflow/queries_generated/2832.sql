-- {"query": "2832.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1921} 
with recursive TagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        array[t.Id] as Path
    from Tags t
    where t.IsRequired = 1

    union all

    select
        child.Id,
        child.TagName,
        child.Count,
        parent.Path || child.Id
    from Tags child
    join TagHierarchy parent on child.Id != all (parent.Path)
    where child.Count > 10 and child.IsRequired = 0
),

FilteredPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        p.ParentId,
        p.AnswerCount,
        dense_rank() over (
            partition by p.OwnerUserId
            order by p.Score desc nulls last, p.CreationDate desc nulls last
        ) as UserPostRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId in (1, 2) -- Questions and Answers only
        and coalesce(p.Score, 0) > 0
        and p.Tags is not null
        and u.Reputation > 1000
),

LatestVotes as (
    select
        v.PostId,
        v.VoteTypeId,
        max(v.CreationDate) as LastVoteDate,
        count(*) filter (where v.VoteTypeId = 2) as UpVotes,
        count(*) filter (where v.VoteTypeId = 3) as DownVotes
    from Votes v
    group by v.PostId, v.VoteTypeId
),

BadgesSummary as (
    select
        b.UserId,
        max(case when b.Class = 1 then 1 else 0 end) as HasGoldBadge,
        max(case when b.Class = 2 then 1 else 0 end) as HasSilverBadge,
        max(case when b.Class = 3 then 1 else 0 end) as HasBronzeBadge,
        count(DISTINCT b.Name) as UniqueBadgesCount
    from Badges b
    group by b.UserId
),

UserActivity as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(bs.HasGoldBadge, 0) as HasGoldBadge,
        coalesce(bs.HasSilverBadge, 0) as HasSilverBadge,
        coalesce(bs.HasBronzeBadge, 0) as HasBronzeBadge,
        bs.UniqueBadgesCount,
        coalesce(max(ph.CreationDate), u.CreationDate) as LastActive,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        row_number() over (order by u.Reputation desc nulls last) as UserRank
    from Users u
    left join BadgesSummary bs on bs.UserId = u.Id
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId in (1,2)
    left join PostHistory ph on ph.PostId = p.Id
    group by u.Id, u.DisplayName, u.Reputation, bs.HasGoldBadge, bs.HasSilverBadge, bs.HasBronzeBadge, bs.UniqueBadgesCount, u.CreationDate
),

QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.OwnerUserId as QuestionOwner,
        q.Title,
        q.Tags,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.AnswerCount,
        coalesce(a.AnswerScore, 0) as TopAnswerScore,
        coalesce(a.OwnerUserId, -1) as TopAnswerOwner,
        a.Id as TopAnswerId,
        a.CreationDate as TopAnswerDate
    from Posts q
    left join lateral (
        select a.Id, a.Score as AnswerScore, a.OwnerUserId, a.CreationDate
        from Posts a
        where a.ParentId = q.Id and a.PostTypeId = 2
        order by a.Score desc nulls last, a.CreationDate asc nulls first
        limit 1
    ) a on true
    where q.PostTypeId = 1
      and q.Score > 5
      and q.AnswerCount > 0
),

DuplicateLinks as (
    select
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId,
        pl.CreationDate as LinkCreationDate
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
),

CloseReasonsSummary as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        count(*) as CloseVotesCount,
        min(ph.CreationDate) as FirstCloseVoteDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int) -- ph.Comment holds CloseReasonId when PostHistoryTypeId=10
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
),

TagPosts as (
    select
        t.TagName,
        count(distinct p.Id) as PostsCount,
        sum(coalesce(p.Score,0)) as TotalScore,
        avg(coalesce(p.ViewCount,0)) as AvgViews,
        max(p.CreationDate) as LastPostDate
    from Tags t
    join Posts p on p.Tags like '%' || '<' || t.TagName || '>' || '%'
    group by t.TagName
    having count(distinct p.Id) > 50
),

EnrichedPosts as (
    select
        fp.*,
        ua.DisplayName as OwnerName,
        ua.Reputation as OwnerReputation,
        ua.HasGoldBadge,
        ua.HasSilverBadge,
        ua.HasBronzeBadge,
        ua.UniqueBadgesCount,
        lv.UpVotes,
        lv.DownVotes,
        crs.CloseReason,
        crs.CloseVotesCount,
        coalesce(dl.OriginalQuestionId, null) as DuplicateOfQuestionId
    from FilteredPosts fp
    left join UserActivity ua on ua.Id = fp.OwnerUserId
    left join LatestVotes lv on lv.PostId = fp.Id and lv.VoteTypeId in (2,3)
    left join CloseReasonsSummary crs on crs.PostId = fp.Id
    left join DuplicateLinks dl on dl.DuplicateQuestionId = fp.Id
),

RankedPosts as (
    select
        ep.*,
        rank() over (
            partition by ep.PostTypeId
            order by coalesce(ep.Score,0) desc nulls last, ep.CreationDate asc nulls first
        ) as PostRank
    from EnrichedPosts ep
),

FinalResults as (
    select
        rp.Id,
        rp.PostTypeId,
        case when rp.PostTypeId = 1 then 'Question' else 'Answer' end as PostType,
        rp.Title,
        rp.OwnerUserId,
        rp.OwnerName,
        rp.OwnerReputation,
        rp.Score,
        rp.UpVotes,
        rp.DownVotes,
        rp.ViewCount,
        rp.AnswerCount,
        rp.HasGoldBadge,
        rp.HasSilverBadge,
        rp.HasBronzeBadge,
        rp.UniqueBadgesCount,
        rp.CloseReason,
        rp.CloseVotesCount,
        rp.DuplicateOfQuestionId,
        rp.CreationDate,
        rp.LastEditDate,
        rp.PostRank,
        count(distinct c.Id) filter (where c.UserId is not null) as CommentsCount,
        string_agg(distinct concat_ws(':', coalesce(u2.DisplayName,'[deleted]'), c.Text), ' || ' order by c.CreationDate) as CommentsSummary
    from RankedPosts rp
    left join Comments c on c.PostId = rp.Id
    left join Users u2 on u2.Id = c.UserId
    where rp.PostRank <= 100
    group by
        rp.Id, rp.PostTypeId, rp.Title, rp.OwnerUserId, rp.OwnerName, rp.OwnerReputation,
        rp.Score, rp.UpVotes, rp.DownVotes, rp.ViewCount, rp.AnswerCount,
        rp.HasGoldBadge, rp.HasSilverBadge, rp.HasBronzeBadge, rp.UniqueBadgesCount,
        rp.CloseReason, rp.CloseVotesCount, rp.DuplicateOfQuestionId,
        rp.CreationDate, rp.LastEditDate, rp.PostRank
    order by rp.PostRank asc
)

select
    fr.*,
    ts.PostsCount as TagPostsCount,
    ts.TotalScore as TagTotalScore,
    ts.AvgViews as TagAvgViews
from FinalResults fr
left join TagPosts ts on ts.TagName = any(string_to_array(substring(fr.Tags from 2 for char_length(fr.Tags)-2), '><'))
limit 50;