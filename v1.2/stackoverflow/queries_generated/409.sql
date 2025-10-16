-- {"query": "409.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1737} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(u.Location, 'Unknown') as Location,
        row_number() over (partition by u.Id order by u.LastAccessDate desc) as rn,
        (select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1) as QuestionCount,
        (select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 2) as AnswerCount,
        (select count(*) from Comments c where c.UserId = u.Id) as CommentCount,
        (select count(distinct b.Name) from Badges b where b.UserId = u.Id and b.Class = 1) as GoldBadges,
        (select count(distinct b.Name) from Badges b where b.UserId = u.Id and b.Class = 2) as SilverBadges,
        (select count(distinct b.Name) from Badges b where b.UserId = u.Id and b.Class = 3) as BronzeBadges
    from Users u
    where u.Reputation > 1000
),
UserRankings as (
    select
        UserId,
        DisplayName,
        Reputation,
        Location,
        QuestionCount,
        AnswerCount,
        CommentCount,
        GoldBadges,
        SilverBadges,
        BronzeBadges,
        row_number() over (order by Reputation desc, QuestionCount desc) as GlobalRank
    from RecursiveUserActivity
    where rn = 1
),
PostStats as (
    select
        p.Id as PostId,
        p.PostTypeId,
        pt.Name as PostTypeName,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        case
            when p.ClosedDate is not null then 1
            else 0
        end as IsClosed,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as UserPostRank
    from Posts p
    left join PostTypes pt on p.PostTypeId = pt.Id
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId in (1, 2) -- Questions and Answers
),
TopPostsWithDuplicates as (
    select
        ps.PostId,
        ps.PostTypeName,
        ps.OwnerUserId,
        ps.OwnerName,
        ps.Score,
        ps.ViewCount,
        ps.CreationDate,
        ps.Title,
        ps.Tags,
        ps.AcceptedAnswerId,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.IsClosed,
        ps.UserPostRank,
        pl.LinkTypeId,
        lt.Name as LinkTypeName,
        pl.RelatedPostId,
        p2.Title as RelatedPostTitle
    from PostStats ps
    left join PostLinks pl on pl.PostId = ps.PostId and pl.LinkTypeId = 3 -- Duplicate link type
    left join LinkTypes lt on pl.LinkTypeId = lt.Id
    left join Posts p2 on pl.RelatedPostId = p2.Id
    where ps.UserPostRank <= 5
),
RankedUserPosts as (
    select
        upr.UserId,
        upr.DisplayName,
        upr.Reputation,
        upr.Location,
        tp.PostId,
        tp.PostTypeName,
        tp.Score,
        tp.ViewCount,
        tp.CreationDate,
        tp.Title,
        tp.Tags,
        tp.IsClosed,
        tp.LinkTypeName,
        tp.RelatedPostTitle,
        rank() over (partition by upr.UserId order by tp.Score desc, tp.ViewCount desc) as PostRank
    from UserRankings upr
    join TopPostsWithDuplicates tp on tp.OwnerUserId = upr.UserId
),
UserBadgeSummary as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldCount,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverCount,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeCount,
        count(distinct b.Name) as UniqueBadges
    from Badges b
    group by b.UserId
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(p.Id) filter (where p.PostTypeId = 1) over (partition by u.Id order by p.CreationDate rows between 365 preceding and current row) as QuestionsLastYear,
        count(p.Id) filter (where p.PostTypeId = 2) over (partition by u.Id order by p.CreationDate rows between 365 preceding and current row) as AnswersLastYear,
        count(c.Id) over (partition by u.Id order by c.CreationDate rows between 365 preceding and current row) as CommentsLastYear
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    where u.Reputation > 1000
),
UserSummary as (
    select
        ur.UserId,
        ur.DisplayName,
        ur.Reputation,
        ur.Location,
        coalesce(ua.QuestionsLastYear, 0) as QuestionsLastYear,
        coalesce(ua.AnswersLastYear, 0) as AnswersLastYear,
        coalesce(ua.CommentsLastYear, 0) as CommentsLastYear,
        coalesce(ub.GoldCount, 0) as GoldBadges,
        coalesce(ub.SilverCount, 0) as SilverBadges,
        coalesce(ub.BronzeCount, 0) as BronzeBadges,
        coalesce(ub.UniqueBadges, 0) as UniqueBadges
    from UserRankings ur
    left join UserActivityWindow ua on ua.UserId = ur.UserId
    left join UserBadgeSummary ub on ub.UserId = ur.UserId
)
select
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.Location,
    us.QuestionsLastYear,
    us.AnswersLastYear,
    us.CommentsLastYear,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.UniqueBadges,
    rup.PostId,
    rup.PostTypeName,
    rup.Score,
    rup.ViewCount,
    rup.CreationDate,
    coalesce(rup.Title, '(no title)') as Title,
    coalesce(rup.Tags, '') as Tags,
    case when rup.IsClosed = 1 then 'Closed' else 'Open' end as PostStatus,
    coalesce(rup.LinkTypeName, 'None') as LinkType,
    coalesce(rup.RelatedPostTitle, '(no related post)') as RelatedPostTitle,
    rup.PostRank,
    (select count(*) from Votes v where v.PostId = rup.PostId and v.VoteTypeId = 2) as UpVotes,
    (select count(*) from Votes v where v.PostId = rup.PostId and v.VoteTypeId = 3) as DownVotes,
    (select max(ph.CreationDate) from PostHistory ph where ph.PostId = rup.PostId) as LastEditDate,
    (select string_agg(distinct pht.Name, ', ') from PostHistory ph join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id where ph.PostId = rup.PostId) as HistoryTypes,
    (select count(*) from Comments c where c.PostId = rup.PostId) as CommentCount
from UserSummary us
left join RankedUserPosts rup on rup.UserId = us.UserId and rup.PostRank <= 3
order by us.Reputation desc, us.UserId, rup.Score desc
limit 100;