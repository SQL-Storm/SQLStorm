-- {"query": "2863.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1498} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.IsModeratorOnly,
        t.IsRequired,
        coalesce(t.ExcerptPostId, 0) as ExcerptPostId,
        coalesce(t.WikiPostId, 0) as WikiPostId,
        array[t.TagName] as TagPath
    from Tags t
    where t.IsRequired = 1

    union all

    select
        child.Id,
        child.TagName,
        child.Count,
        child.IsModeratorOnly,
        child.IsRequired,
        coalesce(child.ExcerptPostId, 0),
        coalesce(child.WikiPostId, 0),
        parent.TagPath || child.TagName
    from Tags child
    join RecursiveTagHierarchy parent on child.Id != parent.Id and child.IsModeratorOnly = 0 and array_length(parent.TagPath,1) < 3
    where child.IsRequired = 0
),
QuestionsWithMetrics as (
    select
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Tags,
        u.Reputation as OwnerReputation,
        u.DisplayName as OwnerName,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId in (10, 11)) as CloseReopenEvents,
        max(coalesce(ph.CreationDate, '1900-01-01'::timestamp)) as LastCloseReopenDate,
        case when p.ClosedDate is not null then 1 else 0 end as IsClosed,
        (
            select count(*) 
            from Votes v 
            where v.PostId = p.Id and v.VoteTypeId = 3 /* DownMod */
        ) as DownVotesCount,
        (
            select count(*) 
            from Votes v 
            where v.PostId = p.Id and v.VoteTypeId = 2 /* UpMod */
        ) as UpVotesCount
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId in (10, 11)
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.FavoriteCount, p.Tags, u.Reputation, u.DisplayName, p.ClosedDate
),
UserBadgeRanks as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges
    from Badges b
    group by b.UserId
),
AnswerStats as (
    select
        a.ParentId as QuestionId,
        count(*) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        count(distinct v.UserId) filter (where v.VoteTypeId = 1) as AcceptedAnswerVotes
    from Posts a
    left join Votes v on v.PostId = a.Id and v.VoteTypeId = 1
    where a.PostTypeId = 2
    group by a.ParentId
),
PopularTags as (
    select
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as TagName,
        p.Id as PostId,
        p.Score,
        p.ViewCount
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
TagRankings as (
    select
        pt.TagName,
        count(distinct pt.PostId) as NumQuestions,
        avg(pt.Score) as AvgScore,
        sum(pt.ViewCount) as TotalViews,
        row_number() over (order by avg(pt.Score) desc, count(distinct pt.PostId) desc) as RankByScore
    from PopularTags pt
    group by pt.TagName
),
AcceptedAnswerDetails as (
    select
        q.Id as QuestionId,
        q.AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AcceptedAnswerOwnerId,
        u.Reputation as AcceptedAnswerOwnerReputation
    from Posts q
    left join Posts a on q.AcceptedAnswerId = a.Id
    left join Users u on a.OwnerUserId = u.Id
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
)
select
    q.QuestionId,
    q.Title,
    q.OwnerName,
    q.OwnerReputation,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    q.FavoriteCount,
    q.IsClosed,
    q.CloseReopenEvents,
    q.LastCloseReopenDate,
    q.UpVotesCount,
    q.DownVotesCount,
    coalesce(ab.GoldBadges,0) as OwnerGoldBadges,
    coalesce(ab.SilverBadges,0) as OwnerSilverBadges,
    coalesce(ab.BronzeBadges,0) as OwnerBronzeBadges,
    a.AverageAnswerScore,
    a.MaxAnswerScore,
    a.AcceptedAnswerScore,
    a.AcceptedAnswerOwnerReputation,
    tr.TagName,
    tr.RankByScore,
    string_agg(distinct phs.Name order by phs.Name) filter (where phs.Name is not null) as PostHistoryEventNames
from QuestionsWithMetrics q
left join UserBadgeRanks ab on ab.UserId = q.OwnerUserId
left join AnswerStats a on a.QuestionId = q.QuestionId
left join AcceptedAnswerDetails aad on aad.QuestionId = q.QuestionId
left join TagRankings tr on tr.TagName = (
    select unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) 
    order by 1 limit 1
)
left join PostHistory ph on ph.PostId = q.QuestionId and ph.PostHistoryTypeId in (10,11,12,13,14,15,19,20)
left join PostHistoryTypes phs on phs.Id = ph.PostHistoryTypeId
where q.AnswerCount > 1
group by
    q.QuestionId, q.Title, q.OwnerName, q.OwnerReputation, q.Score, q.ViewCount, q.AnswerCount, q.FavoriteCount, q.IsClosed,
    q.CloseReopenEvents, q.LastCloseReopenDate, q.UpVotesCount, q.DownVotesCount,
    ab.GoldBadges, ab.SilverBadges, ab.BronzeBadges,
    a.AvgAnswerScore, a.MaxAnswerScore,
    aad.AcceptedAnswerScore, aad.AcceptedAnswerOwnerReputation,
    tr.TagName, tr.RankByScore
order by q.Score desc, q.ViewCount desc
limit 25;