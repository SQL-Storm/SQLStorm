-- {"query": "468.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1359} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(u.Location, 'Unknown') as Location,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        count(distinct b.Id) as BadgeCount,
        row_number() over (partition by u.Location order by u.Reputation desc) as LocationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location
),
TopUsers as (
    select UserId, DisplayName, Reputation, Location, QuestionCount, AnswerCount, CommentCount, BadgeCount
    from RecursiveUserActivity
    where LocationRank <= 5
),
UserPostDetails as (
    select
        p.Id as PostId,
        p.PostTypeId,
        pt.Name as PostTypeName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        p.AcceptedAnswerId,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
        case 
            when p.ClosedDate is not null then 'Closed'
            when p.AcceptedAnswerId is not null then 'Answered'
            else 'Open'
        end as PostStatus,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as UserPostRank
    from Posts p
    inner join PostTypes pt on pt.Id = p.PostTypeId
    left join Users u on u.Id = p.OwnerUserId
    where p.OwnerUserId in (select UserId from TopUsers)
),
PostLinkInfo as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        p1.Score as PostScore,
        p2.Score as RelatedPostScore
    from PostLinks pl
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId
    inner join Posts p1 on p1.Id = pl.PostId
    inner join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.PostId in (select PostId from UserPostDetails)
),
PostHistorySummary as (
    select
        ph.PostId,
        ph.PostHistoryTypeId,
        pht.Name as HistoryTypeName,
        count(*) as HistoryCount,
        max(ph.CreationDate) as LastEditDate
    from PostHistory ph
    inner join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    where ph.PostId in (select PostId from UserPostDetails)
    group by ph.PostId, ph.PostHistoryTypeId, pht.Name
),
UserBadgeSummary as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount,
        string_agg(distinct b.Name, ', ') as BadgeNames
    from Badges b
    where b.UserId in (select UserId from TopUsers)
    group by b.UserId, b.Class
),
UserActivityWithBadges as (
    select
        rua.*,
        coalesce(ubs_gold.BadgeCount, 0) as GoldBadges,
        coalesce(ubs_silver.BadgeCount, 0) as SilverBadges,
        coalesce(ubs_bronze.BadgeCount, 0) as BronzeBadges
    from RecursiveUserActivity rua
    left join UserBadgeSummary ubs_gold on ubs_gold.UserId = rua.UserId and ubs_gold.Class = 1
    left join UserBadgeSummary ubs_silver on ubs_silver.UserId = rua.UserId and ubs_silver.Class = 2
    left join UserBadgeSummary ubs_bronze on ubs_bronze.UserId = rua.UserId and ubs_bronze.Class = 3
)
select distinct
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.Location,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.CommentCount,
    ua.BadgeCount,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    upd.PostId,
    upd.PostTypeName,
    upd.Title,
    upd.Score,
    upd.ViewCount,
    upd.PostStatus,
    phs.HistoryTypeName,
    phs.HistoryCount,
    phs.LastEditDate,
    pli.LinkTypeName,
    pli.RelatedPostId,
    pli.RelatedPostScore,
    case 
        when upd.Tags is not null then array_length(string_to_array(trim(both '<>' from upd.Tags), '><'), 1)
        else 0
    end as TagCount,
    case 
        when upd.Title is not null then length(upd.Title) - length(replace(upd.Title, ' ', '')) + 1
        else 0
    end as TitleWordCount,
    (select count(*) from Comments c where c.PostId = upd.PostId and c.UserId = ua.UserId) as UserCommentsOnOwnPost,
    (select count(*) from Votes v where v.PostId = upd.PostId and v.UserId = ua.UserId and v.VoteTypeId = 2) as UserUpVotesOnOwnPost
from UserActivityWithBadges ua
left join UserPostDetails upd on upd.OwnerUserId = ua.UserId and upd.UserPostRank <= 3
left join PostHistorySummary phs on phs.PostId = upd.PostId
left join PostLinkInfo pli on pli.PostId = upd.PostId
where ua.Location is not null
order by ua.Location, ua.Reputation desc, upd.Score desc
limit 100;