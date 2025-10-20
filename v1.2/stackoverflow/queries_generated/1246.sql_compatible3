with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as QuestionAnswers,
        ts.TopUserCount,
        row_number() over (partition by t.TagName order by t.Count desc) as Rank
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    cross join lateral (
        select count(distinct u.Id) as TopUserCount
        from Users u
        join Posts p2 on p2.OwnerUserId = u.Id and p2.Tags like '%' || t.TagName || '%'
        where u.Reputation > 10000 and p2.PostTypeId = 1
    ) ts
    where t.TagName is not null
),
UserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        count(distinct case when p.PostTypeId=1 then p.Id end) as QuestionCount,
        count(distinct case when p.PostTypeId=2 then p.Id end) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end),0) as UpVotesCount,
        coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end),0) as DownVotesCount,
        max(p.CreationDate) as LastPostDate,
        min(p.CreationDate) as FirstPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id 
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.Location
),
TopQuestionsWithActivity as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        row_number() over (order by p.Score desc NULLS LAST) as ScoreRank,
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.CommentCount,
        ua.UpVotesCount,
        ua.DownVotesCount,
        p.Tags
    from Posts p
    left join UserActivity ua on p.OwnerUserId = ua.UserId
    where p.PostTypeId = 1 and p.Score > 10 and p.Tags is not null
),
CloseDuplicateCount as (
    select 
        ph.PostId,
        count(*) as CloseVotesCount,
        sum(case when ph.PostHistoryTypeId = 10 and ph.Comment = '101' then 1 else 0 end) as DuplicateCloseVotes
    from PostHistory ph 
    where ph.PostHistoryTypeId = 10
    group by ph.PostId
),
DuplicatePosts as (
    select pl.PostId, pl.RelatedPostId
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    where lt.Name = 'Duplicate'
),
AcceptedAnswerReputation as (
    select 
        p.Id as QuestionId,
        coalesce(u.Reputation,0) as AcceptedAnswerOwnerReputation,
        a.OwnerUserId as AcceptedAnswerOwnerId,
        a.Score as AcceptedAnswerScore
    from Posts p
    left join Posts a on a.Id = p.AcceptedAnswerId and a.PostTypeId = 2
    left join Users u on a.OwnerUserId = u.Id
    where p.PostTypeId = 1 and p.AcceptedAnswerId is not null
),
AggregatedBadges as (
    select 
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserBadgesRanked as (
    select 
        a.*,
        rank() over (partition by a.Class order by a.BadgeCount desc) as BadgeRank
    from AggregatedBadges a
),
CombinedUserStats as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        coalesce(bgc.GoldCount, 0) as GoldBadges,
        coalesce(bsc.SilverCount, 0) as SilverBadges,
        coalesce(brc.BronzeCount, 0) as BronzeBadges,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.CommentCount,
        ua.UpVotesCount,
        ua.DownVotesCount,
        ua.LastPostDate,
        ua.FirstPostDate,
        ua.Location
    from UserActivity ua
    left join (
        select UserId, BadgeCount as GoldCount from AggregatedBadges where Class = 1
    ) bgc on ua.UserId = bgc.UserId
    left join (
        select UserId, BadgeCount as SilverCount from AggregatedBadges where Class = 2
    ) bsc on ua.UserId = bsc.UserId
    left join (
        select UserId, BadgeCount as BronzeCount from AggregatedBadges where Class = 3
    ) brc on ua.UserId = brc.UserId
),
MainResults as (
    select 
        tq.Id as QuestionId,
        tq.Title,
        tq.CreationDate as QuestionDate,
        tq.Score as QuestionScore,
        coalesce(cd.CloseVotesCount, 0) as TotalCloseVotes,
        coalesce(cd.DuplicateCloseVotes, 0) as DuplicateCloseVotes,
        dq.RelatedPostId as DuplicateOfPostId,
        aar.AcceptedAnswerOwnerId,
        aar.AcceptedAnswerOwnerReputation,
        aar.AcceptedAnswerScore,
        cu.GoldBadges,
        cu.SilverBadges,
        cu.BronzeBadges,
        concat_ws(', ', cu.Location, cast('Reputation:' as varchar), cast(cu.Reputation as varchar)) as UserSummaryInfo,
        cu.QuestionCount,
        cu.AnswerCount,
        cu.CommentCount,
        cu.UpVotesCount,
        cu.DownVotesCount,
        lag(tq.Score) over (order by tq.Score desc NULLS LAST) as PreviousQuestionScore,
        lead(tq.Score) over (order by tq.Score desc NULLS LAST) as NextQuestionScore,
        length(tq.Title) as TitleLength,
        (strpos(lower(tq.Title), 'sql') > 0) as TitleMentionsSQL,
        case when strpos(coalesce(tq.Tags, ''), '<sql>') > 0 then true else false end as HasSQLTag,
        case when coalesce(cu.LastPostDate, timestamp '1900-01-01') < (timestamp '2024-10-01 12:34:56' - interval '1 year') then true else false end as IsInactiveUser,
        tq.Tags
    from TopQuestionsWithActivity tq
    left join CloseDuplicateCount cd on cd.PostId = tq.Id
    left join DuplicatePosts dq on dq.PostId = tq.Id
    left join AcceptedAnswerReputation aar on aar.QuestionId = tq.Id
    left join CombinedUserStats cu on cu.UserId = tq.UserId
    where coalesce(tq.Tags, '') like '%sql%'
)
select *
from (
    select * from MainResults
    union all
    select
        p.Id as QuestionId,
        p.Title || ' (Unscored)' as Title,
        p.CreationDate as QuestionDate,
        p.Score as QuestionScore,
        0 as TotalCloseVotes,
        0 as DuplicateCloseVotes,
        null as DuplicateOfPostId,
        null as AcceptedAnswerOwnerId,
        0 as AcceptedAnswerOwnerReputation,
        0 as AcceptedAnswerScore,
        0 as GoldBadges,
        0 as SilverBadges,
        0 as BronzeBadges,
        'N/A' as UserSummaryInfo,
        0 as QuestionCount,
        0 as AnswerCount,
        0 as CommentCount,
        0 as UpVotesCount,
        0 as DownVotesCount,
        null as PreviousQuestionScore,
        null as NextQuestionScore,
        length(p.Title) as TitleLength,
        false as TitleMentionsSQL,
        false as HasSQLTag,
        true as IsInactiveUser,
        p.Tags
    from Posts p 
    where p.PostTypeId=1 and (p.Tags is null or p.Tags = '')
) t
order by QuestionScore desc NULLS LAST, QuestionDate desc
limit 60;