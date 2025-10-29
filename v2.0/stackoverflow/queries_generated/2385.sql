-- {"query": "2385.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1234} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        coalesce(array_to_string(array_agg(distinct p.Id), ',') ,'') as PostIds
    from Tags t
    left join Posts p on p.Tags like concat('%<', t.TagName, '>%') and p.PostTypeId = 1
    group by t.Id, t.TagName
), UserBadgeRanks as (
    select
        b.UserId,
        b.Name BadgeName,
        b.Class,
        row_number() over (partition by b.UserId order by b.Class, b.Date desc) as BadgeRank
    from Badges b
), PostAnswers as (
    select
        p.Id,
        p.ParentId,
        p.Score,
        p.OwnerUserId,
        p.CreationDate,
        u.Reputation as OwnerReputation,
        ut.CountAcceptedAnswers
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    left join (
        select
            ParentId,
            count(*) filter (where p.Id = p.AcceptedAnswerId) as CountAcceptedAnswers
        from Posts p
        where p.PostTypeId = 2
        group by ParentId
    ) ut on p.ParentId = ut.ParentId
    where p.PostTypeId = 2
), RankedQuestions as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        q.Tags,
        dense_rank() over (order by q.Score desc, q.ViewCount desc) as ScoreRank,
        count(distinct a.Id) as TotalAnswers,
        avg(a.Score) filter (where a.Score is not null) as AvgAnswerScore
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.AnswerCount, q.FavoriteCount, q.Tags
), UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) as PostsCount,
        count(distinct c.Id) as CommentsCount,
        max(p.CreationDate) as LastPostDate,
        min(p.CreationDate) as FirstPostDate,
        count(distinct b.Id) as BadgeCount,
        bool_or(b.Class = 1) as HasGoldBadge
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
), CloseReasonDetails as (
    select phr.PostId, cr.Name CloseReasonName, max(phr.CreationDate) CloseDate
    from PostHistory phr
    join CloseReasonTypes cr on phr.Comment = cr.Id::varchar and phr.PostHistoryTypeId = 10
    group by phr.PostId, cr.Name
), Duplicates as (
    select pl.PostId, pl.RelatedPostId, lt.Name LinkTypeName
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    where lt.Name = 'Duplicate'
), FinalQuestions as (
    select
        q.*,
        cr.CloseReasonName,
        cr.CloseDate,
        count(distinct d.RelatedPostId) as DuplicateCount,
        ua.PostsCount as OwnerPostsCount,
        ua.Reputation as OwnerReputation,
        ua.HasGoldBadge
    from RankedQuestions q
    left join CloseReasonDetails cr on cr.PostId = q.QuestionId
    left join Duplicates d on d.PostId = q.QuestionId
    left join UserActivity ua on ua.UserId = q.OwnerUserId
    group by q.QuestionId, q.Title, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.AnswerCount, q.FavoriteCount, q.Tags, cr.CloseReasonName, cr.CloseDate, ua.PostsCount, ua.Reputation, ua.HasGoldBadge
)
select 
    fq.QuestionId,
    fq.Title,
    fq.Score,
    fq.ViewCount,
    fq.AnswerCount,
    fq.FavoriteCount,
    fq.Tags,
    fq.CloseReasonName,
    fq.CloseDate,
    fq.DuplicateCount,
    fq.OwnerReputation,
    fq.OwnerPostsCount,
    fq.HasGoldBadge,
    ub.BadgeName,
    ub.Class BadgeClass,
    ua.CommentCount,
    ua.LastPostDate,
    ua.FirstPostDate,
    utc.TagName,
    length(fq.Title) + coalesce(fq.Score,0)*2 - coalesce(fq.ViewCount,0)/100 as CustomRankScore,
    row_number() over (
        partition by utc.TagName 
        order by length(fq.Title) + coalesce(fq.Score,0)*2 - coalesce(fq.ViewCount,0)/100 desc
    ) as RankWithinTag
from FinalQuestions fq
left join UserBadgeRanks ub on ub.UserId = fq.OwnerUserId and ub.BadgeRank = 1
left join UserActivity ua on ua.UserId = fq.OwnerUserId
left join RecursiveTagCounts rtc on rtc.TagName = any(string_to_array(regexp_replace(fq.Tags, '[<>]', ' ', 'g'), ' '))
left join Tags utc on utc.TagName = rtc.TagName
where fq.CloseDate is null or fq.CloseDate > now() - interval '365 days'
order by CustomRankScore desc
limit 100;