-- {"query": "265.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2217} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        1 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        t.Id,
        t.TagName,
        t.Count,
        r.Level + 1,
        r.Path || t.Id
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> all(r.Path)
    where t.IsModeratorOnly = 0 and t.IsRequired = 0 and r.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationRanks as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        dense_rank() over (order by u.Reputation desc) as ReputationRank,
        row_number() over (partition by date_trunc('year', u.CreationDate) order by u.Reputation desc) as YearlyRank
    from Users u
    where u.Reputation is not null
),
PostAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreationDate,
        q.OwnerUserId,
        count(a.Id) filter (where a.Score > 0) as PositiveAnswerCount,
        count(a.Id) filter (where a.Score <= 0) as NonPositiveAnswerCount,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.OwnerUserId = q.OwnerUserId then 1 else 0 end) as SelfAnsweredCount
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.OwnerUserId
),
PostVoteAggregates as (
    select
        p.Id as PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as FavoriteVotes,
        sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as TotalBounty
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id
),
LatestPostHistoryEdits as (
    select distinct on (ph.PostId)
        ph.PostId,
        ph.Id as HistoryId,
        ph.PostHistoryTypeId,
        ph.CreationDate as EditDate,
        ph.UserId as EditorUserId,
        ph.UserDisplayName as EditorDisplayName,
        ph.Comment,
        ph.Text
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6) -- Edit Title, Edit Body, Edit Tags
    order by ph.PostId, ph.CreationDate desc
),
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 -- Post Closed
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(c.Id) as CommentsMade,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotesGiven,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotesGiven,
        max(p.CreationDate) as LastPostDate,
        min(p.CreationDate) as FirstPostDate,
        date_part('day', max(p.CreationDate) - min(p.CreationDate)) as ActiveDaysSpan
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
),
TopTagsByQuestionCount as (
    select
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as Tag,
        count(*) as QuestionCount
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
    group by Tag
    order by QuestionCount desc
    limit 10
),
UserTopTagBadges as (
    select
        b.UserId,
        b.Name,
        b.Class,
        b.Date,
        b.TagBased
    from Badges b
    where b.TagBased = 1
),
UserTagBadgeSummary as (
    select
        utb.UserId,
        count(*) filter (where utb.Class = 1) as GoldTagBadges,
        count(*) filter (where utb.Class = 2) as SilverTagBadges,
        count(*) filter (where utb.Class = 3) as BronzeTagBadges
    from UserTopTagBadges utb
    group by utb.UserId
),
QuestionsWithDuplicates as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        count(pl.Id) filter (where lt.Name = 'Duplicate') as DuplicateCount,
        max(pl.CreationDate) filter (where lt.Name = 'Duplicate') as LastDuplicateLinkDate
    from Posts q
    left join PostLinks pl on pl.PostId = q.Id
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate
),
UserReputationAndBadges as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(ubc.Gold,0) as GoldBadges,
        coalesce(ubc.Silver,0) as SilverBadges,
        coalesce(ubc.Bronze,0) as BronzeBadges
    from Users u
    left join (
        select
            UserId,
            sum(case when Class = 1 then BadgeCount else 0 end) as Gold,
            sum(case when Class = 2 then BadgeCount else 0 end) as Silver,
            sum(case when Class = 3 then BadgeCount else 0 end) as Bronze
        from UserBadgeCounts
        group by UserId
    ) ubc on ubc.UserId = u.Id
)
select
    p.Id as PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    coalesce(pva.UpVotes,0) as UpVotes,
    coalesce(pva.DownVotes,0) as DownVotes,
    coalesce(pva.FavoriteVotes,0) as FavoriteVotes,
    coalesce(pva.TotalBounty,0) as TotalBounty,
    pas.PositiveAnswerCount,
    pas.NonPositiveAnswerCount,
    pas.MaxAnswerScore,
    pas.AvgAnswerScore,
    pas.SelfAnsweredCount,
    qd.DuplicateCount,
    qd.LastDuplicateLinkDate,
    qcr.CloseReasonName,
    qcr.CloseDate,
    lph.EditDate as LastEditDate,
    lph.EditorUserId,
    lph.EditorDisplayName,
    lph.PostHistoryTypeId,
    ur.DisplayName as OwnerDisplayName,
    ur.Reputation as OwnerReputation,
    ur.GoldBadges,
    ur.SilverBadges,
    ur.BronzeBadges,
    ua.QuestionsPosted,
    ua.AnswersPosted,
    ua.CommentsMade,
    ua.UpVotesGiven,
    ua.DownVotesGiven,
    ua.LastPostDate,
    ua.FirstPostDate,
    ua.ActiveDaysSpan,
    ts.TagName,
    ts.Count as TagGlobalCount,
    utbs.GoldTagBadges,
    utbs.SilverTagBadges,
    utbs.BronzeTagBadges,
    row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as PostRankWithinType,
    dense_rank() over (order by p.Score desc) as GlobalPostScoreRank,
    case
        when p.ClosedDate is not null then 'Closed'
        when pas.PositiveAnswerCount > 5 then 'Popular'
        else 'Normal'
    end as PostStatus,
    concat_ws(' | ',
        coalesce(p.Title, 'No Title'),
        coalesce(ur.DisplayName, 'Anonymous'),
        coalesce(qcr.CloseReasonName, 'Open'),
        coalesce(ts.TagName, 'NoTag')
    ) as CompositeString
from Posts p
left join PostVoteAggregates pva on pva.PostId = p.Id
left join PostAnswerStats pas on pas.QuestionId = p.Id and p.PostTypeId = 1
left join QuestionsWithDuplicates qd on qd.QuestionId = p.Id and p.PostTypeId = 1
left join QuestionCloseReasons qcr on qcr.PostId = p.Id and p.PostTypeId = 1
left join LatestPostHistoryEdits lph on lph.PostId = p.Id
left join UserReputationAndBadges ur on ur.Id = p.OwnerUserId
left join UserActivityWindow ua on ua.UserId = p.OwnerUserId
left join (
    select
        t.TagName,
        t.Count
    from Tags t
    join TopTagsByQuestionCount tt on tt.Tag = t.TagName
) ts on position(concat('<', ts.TagName, '>') in p.Tags) > 0
left join UserTagBadgeSummary utbs on utbs.UserId = p.OwnerUserId
where p.PostTypeId in (1,2)
order by p.Score desc, p.ViewCount desc
limit 100;