-- {"query": "245.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1754} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        count(distinct b.Id) as BadgeCount,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopUsers as (
    select UserId, DisplayName, Reputation, QuestionCount, AnswerCount, CommentCount, BadgeCount, UserRank
    from RecursiveUserActivity
    where UserRank <= 100
),
PostDetails as (
    select
        p.Id,
        p.PostTypeId,
        pt.Name as PostTypeName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        p.AcceptedAnswerId,
        p.ParentId,
        p.Tags,
        p.Title,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.LastActivityDate,
        case when p.ClosedDate is not null then 1 else 0 end as IsClosed,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as PostRank
    from Posts p
    left join PostTypes pt on pt.Id = p.PostTypeId
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId in (1, 2)
),
AcceptedAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId as QuestionOwnerId,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        a.Id as AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AnswerOwnerId,
        a.CreationDate as AnswerCreationDate,
        a.Score - q.Score as ScoreDifference,
        case when a.Score > q.Score then 'AnswerBetter' else 'QuestionBetterOrEqual' end as ScoreComparison
    from PostDetails q
    left join PostDetails a on a.Id = q.AcceptedAnswerId
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
UserBadgeSummary as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
UserVoteActivity as (
    select
        v.UserId,
        vt.Name as VoteTypeName,
        count(*) as VoteCount
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    where v.UserId is not null
    group by v.UserId, vt.Name
),
PostLinkSummary as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Linked') as LinkedCount,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Duplicate') as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
),
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 and ph.Comment is not null and ph.Comment ~ '^\d+$'
    group by ph.PostId, crt.Name
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(c.Id) as CommentsMade,
        sum(v.BountyAmount) filter (where v.BountyAmount is not null) as TotalBountyGiven,
        row_number() over (partition by u.Id order by p.CreationDate desc nulls last) as RecentPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id and v.BountyAmount is not null
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
UserStringConcat as (
    select
        u.Id as UserId,
        string_agg(distinct b.Name, ', ' order by b.Name) as BadgeNames,
        string_agg(distinct vt.Name, ', ' order by vt.Name) as VoteTypesCast
    from Users u
    left join Badges b on b.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join VoteTypes vt on vt.Id = v.VoteTypeId
    group by u.Id
)
select
    tu.UserRank,
    tu.DisplayName,
    tu.Reputation,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.CommentCount,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    coalesce(uv.VoteCount, 0) as TotalVotesCast,
    coalesce(pl.LinkedCount, 0) as TotalLinkedPosts,
    coalesce(pl.DuplicateCount, 0) as TotalDuplicatePosts,
    coalesce(qcr.CloseCount, 0) as TotalCloseVotes,
    qcr.CloseReasonName,
    aas.ScoreDifference,
    aas.ScoreComparison,
    ua.TotalBountyGiven,
    ua.RecentPostRank,
    us.BadgeNames,
    us.VoteTypesCast,
    case
        when tu.Reputation > 10000 and tu.AnswerCount > tu.QuestionCount then 'Expert Answerer'
        when tu.Reputation > 10000 and tu.QuestionCount >= tu.AnswerCount then 'Expert Questioner'
        else 'Regular User'
    end as UserCategory,
    case
        when aas.ScoreDifference is null then 'No Accepted Answer'
        when aas.ScoreDifference > 0 then 'Accepted Answer Outperforms Question'
        else 'Question Outperforms Accepted Answer'
    end as AcceptedAnswerPerformance
from TopUsers tu
left join UserBadgeSummary ubs on ubs.UserId = tu.UserId
left join UserVoteActivity uv on uv.UserId = tu.UserId
left join PostLinkSummary pl on pl.PostId = (
    select p.Id from Posts p where p.OwnerUserId = tu.UserId order by p.Score desc limit 1
)
left join QuestionCloseReasons qcr on qcr.PostId = (
    select p.Id from Posts p where p.OwnerUserId = tu.UserId and p.PostTypeId = 1 order by p.ClosedDate desc nulls last limit 1
)
left join AcceptedAnswerStats aas on aas.QuestionOwnerId = tu.UserId
left join UserActivityWindow ua on ua.UserId = tu.UserId
left join UserStringConcat us on us.UserId = tu.UserId
order by tu.UserRank
limit 100;