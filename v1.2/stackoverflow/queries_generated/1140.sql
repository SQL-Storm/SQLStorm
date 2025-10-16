-- {"query": "1140.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1487} 
with RecursivePostHierarchy as (
    select p.Id, p.ParentId, 1 as Level, p.PostTypeId, p.Score, p.CreationDate, p.OwnerUserId
    from Posts p
    where p.PostTypeId = 1 -- questions only, roots
    
    union all
    
    select c.Id, c.ParentId, r.Level + 1, c.PostTypeId, c.Score, c.CreationDate, c.OwnerUserId
    from Posts c
    join RecursivePostHierarchy r on c.ParentId = r.Id and c.PostTypeId = 2 -- answers linked to questions recursively
),
UserBadgeSummary as (
    select 
        b.UserId,
        count(*) as BadgeCount,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        bool_or(b.TagBased = 1) as HasTagBasedBadge,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
QuestionScoreRanks as (
    select 
        p.Id,
        p.Title,
        p.ViewCount,
        p.Score,
        p.CreationDate,
        p.OwnerUserId,
        rank() over (partition by date_trunc('month', p.CreationDate) order by p.Score desc nulls last) as MonthlyScoreRank,
        dense_rank() over (order by p.ViewCount desc nulls last) as OverallViewRank
    from Posts p
    where p.PostTypeId = 1
),
ClosedQuestionsCTE as (
    select p.Id, p.Title, p.ClosedDate, p.OwnerUserId, ph.Comment as CloseReasonId, crt.Name as CloseReason
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id::text = ph.Comment
    where p.PostTypeId = 1 and p.ClosedDate is not null
),
TopCommenters as (
    select 
        c.UserId, 
        u.DisplayName,
        count(*) as CommentCount,
        sum(case when length(c.Text) > 300 then 1 else 0 end) as LongComments,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    left join Users u on u.Id = c.UserId
    group by c.UserId, u.DisplayName
    having count(*) >= 50
),
PostVoteAggregates as (
    select 
        v.PostId,
        count(*) filter (where v.VoteTypeId = 2) as UpVotes,
        count(*) filter (where v.VoteTypeId = 3) as DownVotes,
        count(*) filter (where v.VoteTypeId = 5) as Favorites,
        count(distinct v.UserId) as VoterCount,
        sum(case when v.BountyAmount is not null then v.BountyAmount else 0 end) as TotalBounty
    from Votes v
    group by v.PostId
),
UserActivityStats as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        coalesce(b.BadgeCount,0) as BadgeCount,
        coalesce(b.GoldBadges,0) as GoldBadges,
        coalesce(b.SilverBadges,0) as SilverBadges,
        coalesce(b.BronzeBadges,0) as BronzeBadges
    from Users u
    left join UserBadgeSummary b on b.UserId = u.Id
),
LatestPostHistories as (
    select distinct on (ph.PostId)
        ph.PostId,
        ph.Id as PostHistoryId,
        ph.PostHistoryTypeId,
        ph.CreationDate as HistoryDate,
        ph.UserId as EditorUserId,
        ph.UserDisplayName as EditorName,
        ph.Comment as EditComment,
        ph.Text as EditText
    from PostHistory ph
    order by ph.PostId, ph.CreationDate desc
)
select 
    q.Id as QuestionId,
    q.Title,
    q.CreationDate as QuestionCreated,
    u.DisplayName as QuestionOwner,
    uas.Reputation as OwnerReputation,
    q.ViewCount,
    q.Score as QuestionScore,
    coalesce(pva.UpVotes, 0) as ScoreUpVotes,
    coalesce(pva.DownVotes, 0) as ScoreDownVotes,
    coalesce(pva.Favorites, 0) as FavoriteCount,
    coalesce(pva.TotalBounty, 0) as TotalBountyAmount,
    q.MonthlyScoreRank,
    q.OverallViewRank,
    cs.ClosedDate,
    cs.CloseReason,
    ts.DisplayName as TopCommenterName,
    ts.CommentCount as TopCommenterComments,
    ts.LongComments as TopCommenterLongComments,
    ts.LastCommentDate as TopCommenterLastComment,
    uh.GoldBadges,
    uh.SilverBadges,
    uh.BronzeBadges,
    -- window function example: cumulative sum of scores of all questions by this user ordered by creation date
    sum(q.Score) over (partition by q.OwnerUserId order by q.CreationDate rows between unbounded preceding and current row) as UserCumulativeQuestionScore,
    -- string expressions: tag count and tags concatenated (using NULL logic for tags)
    length(regexp_replace(coalesce(p.Tags,''), '[<>]', '', 'g')) as TagStringLength,
    array_length(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><'), 1) as TagCount,
    -- Correlated subquery: count of answers for question ignoring soft deleted answers with scores above average for that question owner
    (select count(*) 
     from Posts a 
     where a.ParentId = q.Id AND a.Score > (select avg(Score) from Posts where OwnerUserId = q.OwnerUserId) AND a.PostTypeId=2) as HighScoreAnswerCount,
    lph.PostHistoryTypeId as LastPostHistoryType,
    lph.EditComment as LastEditComment
    
from QuestionScoreRanks q
left join Posts p on p.Id = q.Id
left join Users u on u.Id = q.OwnerUserId
left join UserActivityStats uas on uas.Id = u.Id
left join ClosedQuestionsCTE cs on cs.Id = q.Id
left join TopCommenters ts on ts.UserId = u.Id
left join PostVoteAggregates pva on pva.PostId = q.Id
left join UserBadgeSummary uh on uh.UserId = u.Id
left join LatestPostHistories lph on lph.PostId = q.Id

where q.MonthlyScoreRank <= 100
order by q.MonthlyScoreRank, q.ViewCount desc
limit 100;