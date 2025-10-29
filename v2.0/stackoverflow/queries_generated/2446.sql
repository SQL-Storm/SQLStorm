-- {"query": "2446.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2059} 
with RecursiveCTE as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        tags_array.tag,
        row_number() over (partition by p.Id order by p.CreationDate) as tag_seq,
        1 as level
    from
        Posts p
        cross join lateral (
            select unnest(string_to_array(substring(coalesce(p.Tags, ''), 2, length(coalesce(p.Tags, '')) - 2), '><')) as tag
        ) tags_array

    union all

    select
        r.Id,
        r.PostTypeId,
        r.OwnerUserId,
        r.Score,
        r.ViewCount,
        r.CreationDate,
        r.tag,
        r.tag_seq,
        level + 1
    from RecursiveCTE r
    where level < 1 -- no real recursion, placeholder for complexity
),
UserBadgeCount as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges
    from Badges b
    group by b.UserId
),
PostCommentsAgg as (
    select
        c.PostId,
        count(*) as CommentCount,
        sum(c.Score) as TotalCommentScore,
        max(c.CreationDate) as LastCommentDate,
        string_agg(distinct c.UserDisplayName, ', ' order by c.CreationDate desc) as RecentCommenters
    from Comments c
    group by c.PostId
),
PostAcceptedAnswerDetails as (
    select
        q.Id as QuestionId,
        a.Id as AcceptedAnswerId,
        a.Score as AnswerScore,
        a.ViewCount as AnswerViewCount,
        a.OwnerUserId as AnswerOwnerUserId,
        u.DisplayName as AnswerOwnerDisplayName,
        row_number() over (partition by q.Id order by a.Score desc) rn
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
),
DuplicateLinksCount as (
    select
        pl.PostId,
        count(*) filter (where pl.LinkTypeId = 3) as DuplicateCount,
        bool_or(pl.CreationDate > current_date - interval '30 days') as HasRecentDuplicateLink
    from PostLinks pl
    group by pl.PostId
),
PostHistoryCloseInfo as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as LastCloseDate,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate end) as LastReopenDate,
        count(*) filter (where ph.PostHistoryTypeId = 10) as CloseCount,
        count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenCount,
        max(c.CloseReasonTypes.Name) as CloseReasonName
    from PostHistory ph
    left join CloseReasonTypes c on c.Id = cast(ph.Comment as integer) and ph.PostHistoryTypeId = 10
    group by ph.PostId
),
UserActivityRank as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TopTagsByCount as (
    select
        t.TagName,
        t.Count,
        p.Id as ExcerptPostId,
        string_agg(distinct u.DisplayName, ', ' order by u.Reputation desc) as TopTagOwners
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId
    left join Users u on u.Id = p.OwnerUserId
    group by t.TagName, t.Count, p.Id
),
CombinedQuestions as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName,
        array_agg(distinct r.tag) filter (where r.tag is not null) as Tags,
        coalesce(dc.DuplicateCount, 0) as DuplicateCount,
        coalesce(dc.HasRecentDuplicateLink, false) as HasRecentDuplicateLink,
        coalesce(pc.CommentCount, 0) as CommentCount,
        coalesce(pc.TotalCommentScore, 0) as TotalCommentScore,
        aca.AcceptedAnswerId,
        aca.AnswerScore,
        aca.AnswerViewCount,
        aca.AnswerOwnerUserId,
        aca.AnswerOwnerDisplayName,
        phci.LastCloseDate,
        phci.LastReopenDate,
        phci.CloseCount,
        phci.ReopenCount,
        phci.CloseReasonName,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join RecursiveCTE r on r.Id = p.Id
    left join DuplicateLinksCount dc on dc.PostId = p.Id
    left join PostCommentsAgg pc on pc.PostId = p.Id
    left join PostAcceptedAnswerDetails aca on aca.QuestionId = p.Id
    left join PostHistoryCloseInfo phci on phci.PostId = p.Id
    left join UserBadgeCount ub on ub.UserId = p.OwnerUserId
    where p.PostTypeId = 1
    group by
        p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate,
        p.OwnerUserId, u.DisplayName, dc.DuplicateCount, dc.HasRecentDuplicateLink,
        pc.CommentCount, pc.TotalCommentScore, aca.AcceptedAnswerId, aca.AnswerScore, aca.AnswerViewCount,
        aca.AnswerOwnerUserId, aca.AnswerOwnerDisplayName, phci.LastCloseDate, phci.LastReopenDate,
        phci.CloseCount, phci.ReopenCount, phci.CloseReasonName, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges
),
QuestionRanks as (
    select
        cq.*,
        dense_rank() over (order by cq.Score desc, cq.ViewCount desc, array_length(cq.Tags, 1) desc nulls last) as PopularityRank,
        ntile(4) over (order by cq.CreationDate) as CreationQuartile
    from CombinedQuestions cq
),
FinalSelection as (
    select
        qr.Id as QuestionId,
        qr.Title as QuestionTitle,
        qr.Score as QuestionScore,
        qr.ViewCount as QuestionViews,
        qr.CreationDate as AskedOn,
        qr.DisplayName as AskedBy,
        qr.GoldBadges, qr.SilverBadges, qr.BronzeBadges,
        qr.Tags,
        qr.DuplicateCount,
        qr.HasRecentDuplicateLink,
        qr.CommentCount,
        qr.TotalCommentScore,
        qr.AcceptedAnswerId,
        qr.AnswerScore,
        qr.AnswerViewCount,
        qr.AnswerOwnerUserId,
        qr.AnswerOwnerDisplayName,
        qr.LastCloseDate,
        qr.LastReopenDate,
        qr.CloseCount,
        qr.ReopenCount,
        qr.CloseReasonName,
        qr.PopularityRank,
        qr.CreationQuartile,
        (select string_agg(distinct vt.Name, ', ')
         from Votes v
         join VoteTypes vt on vt.Id = v.VoteTypeId
         where v.PostId = qr.Id and v.CreationDate > current_date - interval '90 days') as RecentVoteTypes,
        case 
            when qr.Score > 100 then 'Hot Question'
            when qr.DuplicateCount > 3 then 'Likely Duplicate'
            when qr.CloseCount > qr.ReopenCount then 'Closed'
            when coalesce(qr.HasRecentDuplicateLink, false) = true then 'Duplicate Recently Linked'
            else 'Normal'
        end as StatusLabel
    from QuestionRanks qr
    where qr.PopularityRank <= 100
)
select 
    fs.QuestionId,
    fs.QuestionTitle,
    fs.AskedBy,
    fs.AskedOn,
    fs.QuestionScore,
    fs.QuestionViews,
    fs.GoldBadges,
    fs.SilverBadges,
    fs.BronzeBadges,
    coalesce(array_to_string(fs.Tags, ', '), 'No Tags') as TagList,
    fs.DuplicateCount,
    fs.HasRecentDuplicateLink,
    fs.CommentCount,
    fs.TotalCommentScore,
    fs.AcceptedAnswerId,
    fs.AnswerScore,
    fs.AnswerViewCount,
    fs.AnswerOwnerUserId,
    fs.AnswerOwnerDisplayName,
    fs.LastCloseDate,
    fs.LastReopenDate,
    fs.CloseCount,
    fs.ReopenCount,
    fs.CloseReasonName,
    fs.RecentVoteTypes,
    fs.StatusLabel,
    fs.PopularityRank,
    fs.CreationQuartile
from FinalSelection fs
order by fs.PopularityRank, fs.QuestionScore desc, fs.QuestionViews desc
limit 50;