-- {"query": "224.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1013} 
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
        coalesce(sum(v.VoteCount),0) as TotalVotesReceived,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        where VoteTypeId in (2,3) -- UpMod and DownMod
        group by PostId
    ) v on v.PostId = p.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
), TopUsers as (
    select * from RecursiveUserActivity where UserRank <= 100
), PostWithBadges as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        b.Name as BadgeName,
        b.Class as BadgeClass,
        b.Date as BadgeDate
    from Posts p
    left join Badges b on b.UserId = p.OwnerUserId
    where p.PostTypeId in (1,2)
), RankedPosts as (
    select
        pwb.*,
        row_number() over (partition by pwb.OwnerUserId order by pwb.Score desc, pwb.CreationDate desc) as PostRank
    from PostWithBadges pwb
), UserTopPosts as (
    select * from RankedPosts where PostRank <= 5
), DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where pl.LinkTypeId = 3 -- Duplicate
), QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 -- Post Closed
), UserActivitySummary as (
    select
        u.UserId,
        u.DisplayName,
        u.Reputation,
        u.QuestionCount,
        u.AnswerCount,
        u.CommentCount,
        u.TotalVotesReceived,
        count(distinct qcr.PostId) as ClosedQuestionsCount,
        count(distinct dl.PostId) as DuplicatePostsCount,
        max(p.CreationDate) as LastPostDate
    from RecursiveUserActivity u
    left join Posts p on p.OwnerUserId = u.UserId
    left join QuestionCloseReasons qcr on qcr.PostId = p.Id and p.PostTypeId = 1
    left join DuplicateLinks dl on dl.PostId = p.Id
    group by u.UserId, u.DisplayName, u.Reputation, u.QuestionCount, u.AnswerCount, u.CommentCount, u.TotalVotesReceived
)
select
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.CommentCount,
    uas.TotalVotesReceived,
    uas.ClosedQuestionsCount,
    uas.DuplicatePostsCount,
    uas.LastPostDate,
    utp.PostId,
    utp.PostTypeId,
    utp.Title,
    utp.Score,
    utp.ViewCount,
    utp.BadgeName,
    utp.BadgeClass,
    utp.BadgeDate,
    case 
        when utp.Tags is null then 'No Tags'
        else array_to_string(string_to_array(substring(utp.Tags from 2 for length(utp.Tags)-2), '><'), ', ')
    end as ParsedTags,
    row_number() over (partition by uas.UserId order by utp.Score desc) as PostOrderByScore
from UserActivitySummary uas
left join UserTopPosts utp on utp.OwnerUserId = uas.UserId
where uas.Reputation > 1000
  and (uas.QuestionCount + uas.AnswerCount) > 10
order by uas.Reputation desc, uas.UserId, PostOrderByScore
limit 200;