with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate as PostCreationDate,
        case when p.PostTypeId = 1 then coalesce(p.AcceptedAnswerId, -1) else -1 end as AcceptedAnswerId,
        p.Score as PostScore,
        p.Title,
        p.Tags,
        row_number() over (partition by u.Id order by p.CreationDate desc) as PostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 100 and u.LastAccessDate > cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
),
UserBadgeSummary as (
    select 
        b.UserId,
        count(*) as TotalBadges,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        max(b.Date) as MostRecentBadgeDate,
        string_agg(distinct b.Name, ', ' order by b.Name) as BadgeNames
    from Badges b
    group by b.UserId
),
TopPostsWithAnswerStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        coalesce(a.AnswerCount, 0) as AnswerCount,
        coalesce(a.AcceptedAnswerScore, -1) as AcceptedAnswerScore,
        coalesce(a.MaxAnswerScore, -1) as MaxAnswerScore,        
        p.Tags,
        p.CreationDate,
        p.LastActivityDate
    from Posts p
    left join (
        select 
            a.ParentId as ParentId,
            count(*) as AnswerCount,
            max(case when a.ParentId = q.Id and a.Id = q.AcceptedAnswerId then a.Score else null end) as AcceptedAnswerScore,
            max(a.Score) as MaxAnswerScore
        from Posts a
        join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
        where a.PostTypeId = 2
        group by a.ParentId
    ) a on a.ParentId = p.Id
    where p.PostTypeId = 1 and p.Score > 10 and p.ViewCount > 1000
),
CloseReasonCounts as (
    select
        cht.Name as CloseReasonName,
        count(distinct ph.PostId) as ClosedPostsCount
    from PostHistory ph
    join PostHistoryTypes chtype on chtype.Id = ph.PostHistoryTypeId and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes cht on cast(cht.Id as varchar) = ph.Comment
    where ph.PostHistoryTypeId = 10
    group by cht.Name
),
UserCommentStats as (
    select
        c.UserId,
        u.DisplayName,
        count(*) as TotalComments,
        avg(length(c.Text)) as AvgCommentLength,
        count(distinct c.PostId) as DistinctPostsCommented,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    left join Users u on u.Id = c.UserId
    where c.UserId is not null
    group by c.UserId, u.DisplayName
),
UserVotesReceived as (
    select
        p.OwnerUserId as UserId,
        count(case when v.VoteTypeId = 2 then 1 end) as UpVotesReceived,
        count(case when v.VoteTypeId = 3 then 1 end) as DownVotesReceived,
        count(case when v.VoteTypeId = 5 then 1 end) as FavoritesReceived
    from Votes v
    join Posts p on p.Id = v.PostId
    group by p.OwnerUserId
)
select 
    r.UserId,
    r.DisplayName,
    r.Reputation,
    r.PostId,
    r.PostTypeId,
    r.PostCreationDate,
    r.AcceptedAnswerId,
    r.PostScore,
    r.Title,
    coalesce(ubs.TotalBadges, 0) as TotalBadges,
    coalesce(ubs.GoldBadges, 0) as GoldBadges,
    coalesce(ubs.SilverBadges, 0) as SilverBadges,
    coalesce(ubs.BronzeBadges, 0) as BronzeBadges,
    ucs.TotalComments,
    ucs.AvgCommentLength,
    ucs.DistinctPostsCommented,
    coalesce(uvr.UpVotesReceived, 0) as UpVotesReceived,
    coalesce(uvr.DownVotesReceived, 0) as DownVotesReceived,
    coalesce(uvr.FavoritesReceived, 0) as FavoritesReceived,
    tpa.QuestionId,
    tpa.Title as QuestionTitle,
    tpa.Score as QuestionScore,
    tpa.ViewCount as QuestionViews,
    tpa.AnswerCount,
    tpa.AcceptedAnswerScore,
    tpa.MaxAnswerScore,
    tpa.Tags as QuestionTags,
    tpa.CreationDate as QuestionCreationDate,
    tpa.LastActivityDate as QuestionLastActivityDate,
    crc.CloseReasonName,
    crc.ClosedPostsCount,
    concat_ws(' | ', 
        r.Title,
        substring(r.Tags from 2 for length(r.Tags)-2),
        'Score: ' || cast(r.PostScore as text),
        'Reputation: ' || cast(r.Reputation as text),
        'Badges: ' || cast(coalesce(ubs.TotalBadges, 0) as text)
    ) as CompositeString,
    case 
        when r.PostScore > 0 then 'Positive'
        when r.PostScore = 0 then 'Neutral'
        else 'Negative'
    end as PostSentiment,
    row_number() over (partition by r.UserId order by r.PostCreationDate desc) as RowNumPerUser,
    rank() over (order by r.Reputation desc) as UserRankByReputation
from RecursiveUserActivity r
left join UserBadgeSummary ubs on ubs.UserId = r.UserId
left join UserCommentStats ucs on ucs.UserId = r.UserId
left join UserVotesReceived uvr on uvr.UserId = r.UserId
left join TopPostsWithAnswerStats tpa on tpa.QuestionId = r.PostId
left join CloseReasonCounts crc on crc.CloseReasonName is not null
where r.PostRank <= 3 and r.PostTypeId in (1, 2)

union

select 
    r.UserId,
    r.DisplayName,
    r.Reputation,
    r.PostId,
    r.PostTypeId,
    r.PostCreationDate,
    r.AcceptedAnswerId,
    r.PostScore,
    r.Title,
    0 as TotalBadges,
    0 as GoldBadges,
    0 as SilverBadges,
    0 as BronzeBadges,
    0 as TotalComments,
    0 as AvgCommentLength,
    0 as DistinctPostsCommented,
    0 as UpVotesReceived,
    0 as DownVotesReceived,
    0 as FavoritesReceived,
    null as QuestionId,
    null as QuestionTitle,
    null as QuestionScore,
    null as QuestionViews,
    null as AnswerCount,
    null as AcceptedAnswerScore,
    null as MaxAnswerScore,
    null as QuestionTags,
    null as QuestionCreationDate,
    null as QuestionLastActivityDate,
    null as CloseReasonName,
    null as ClosedPostsCount,
    concat_ws(' | ', 
        r.Title,
        substring(r.Tags from 2 for length(r.Tags)-2),
        'Score: ' || cast(r.PostScore as text),
        'Reputation: ' || cast(r.Reputation as text)
    ) as CompositeString,
    case 
        when r.PostScore > 0 then 'Positive'
        when r.PostScore = 0 then 'Neutral'
        else 'Negative'
    end as PostSentiment,
    row_number() over (partition by r.UserId order by r.PostCreationDate desc) as RowNumPerUser,
    rank() over (order by r.Reputation desc) as UserRankByReputation
from RecursiveUserActivity r
left join UserBadgeSummary ubs on ubs.UserId = r.UserId
left join UserCommentStats ucs on ucs.UserId = r.UserId
left join UserVotesReceived uvr on uvr.UserId = r.UserId
left join TopPostsWithAnswerStats tpa on tpa.QuestionId = r.PostId
left join CloseReasonCounts crc on crc.CloseReasonName is not null
where r.PostRank <= 3 and r.PostTypeId not in (1, 2)
order by UserRankByReputation, UserId, RowNumPerUser
limit 100;