-- {"query": "515.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2040} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        array[t.Id] as Ancestors
    from Tags t
    where t.IsRequired = 1
    union all
    select
        t.Id,
        t.TagName,
        t.Count,
        r.Ancestors || t.Id
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> all(r.Ancestors)
    where t.Count > 10 and t.IsModeratorOnly = 0
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
TopPostsWithVotes as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Tags,
        coalesce(v.UpVotes,0) as UpVotes,
        coalesce(v.DownVotes,0) as DownVotes,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as RankByScore
    from Posts p
    left join (
        select
            PostId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId
        group by PostId
    ) v on v.PostId = p.Id
    where p.PostTypeId in (1,2) -- questions and answers
),
AcceptedAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId as QuestionOwner,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerOwner,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
PostCommentsSummary as (
    select
        c.PostId,
        count(*) as CommentCount,
        avg(length(c.Text)) as AvgCommentLength,
        max(c.CreationDate) as LastCommentDate,
        count(distinct c.UserId) as UniqueCommenters
    from Comments c
    group by c.PostId
),
ComplexFilteredPosts as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        ph.PostHistoryTypeId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        pcs.CommentCount,
        pcs.AvgCommentLength,
        pcs.UniqueCommenters,
        u.DisplayName as OwnerName,
        u.Reputation,
        u.CreationDate as UserCreationDate,
        u.Location,
        u.AboutMe,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.LastAccessDate,
        u.WebsiteUrl,
        u.ProfileImageUrl,
        u.EmailHash,
        u.AccountId
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10 -- Post Closed
    left join CloseReasonTypes crt on crt.Id::int = ph.Comment::int
    left join PostCommentsSummary pcs on pcs.PostId = p.Id
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
      and (p.Score > 10 or p.ViewCount > 1000)
      and (crt.Name is null or crt.Name not in ('Exact Duplicate', 'Duplicate'))
      and (p.Tags is not null and length(p.Tags) > 0)
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        count(distinct c.Id) as CommentsCount,
        max(p.CreationDate) as LastPostDate,
        min(p.CreationDate) as FirstPostDate,
        max(c.CreationDate) as LastCommentDate,
        min(c.CreationDate) as FirstCommentDate,
        lead(u.Reputation) over (order by u.Reputation desc) as NextHigherReputation,
        lag(u.Reputation) over (order by u.Reputation desc) as NextLowerReputation
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
CombinedResults as (
    select
        cp.Id as QuestionId,
        cp.Title,
        cp.Tags,
        cp.Score,
        cp.ViewCount,
        cp.OwnerUserId,
        cp.OwnerName,
        cp.Reputation as OwnerReputation,
        cp.CloseDate,
        cp.CloseReason,
        cp.CommentCount,
        cp.AvgCommentLength,
        cp.UniqueCommenters,
        ua.QuestionsCount,
        ua.AnswersCount,
        ua.CommentsCount,
        ua.LastPostDate,
        ua.FirstPostDate,
        ua.LastCommentDate,
        ua.FirstCommentDate,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        ubs.TagBasedBadges,
        ubs.LastBadgeDate,
        tth.TagName,
        tas.AnswerId,
        tas.AnswerScore,
        tas.AnswerCreationDate,
        tas.AnswerOwner
    from ComplexFilteredPosts cp
    left join UserActivityWindow ua on ua.UserId = cp.OwnerUserId
    left join UserBadgeStats ubs on ubs.UserId = cp.OwnerUserId
    left join RecursiveTagHierarchy tth on tth.TagName = (select unnest(string_to_array(substring(cp.Tags from 2 for char_length(cp.Tags)-2), '><')) limit 1)
    left join AcceptedAnswerStats tas on tas.QuestionId = cp.Id
    where cp.Score > 20 or cp.ViewCount > 5000
    order by cp.Score desc, cp.ViewCount desc
    limit 100
)
select
    cr.QuestionId,
    cr.Title,
    cr.Tags,
    cr.Score,
    cr.ViewCount,
    cr.OwnerUserId,
    cr.OwnerName,
    cr.OwnerReputation,
    cr.GoldBadges,
    cr.SilverBadges,
    cr.BronzeBadges,
    cr.TagBasedBadges,
    cr.CloseDate,
    cr.CloseReason,
    cr.CommentCount,
    round(cr.AvgCommentLength,2) as AvgCommentLength,
    cr.UniqueCommenters,
    cr.QuestionsCount,
    cr.AnswersCount,
    cr.CommentsCount,
    cr.LastPostDate,
    cr.FirstPostDate,
    cr.LastCommentDate,
    cr.FirstCommentDate,
    cr.TagName,
    cr.AnswerId,
    cr.AnswerScore,
    cr.AnswerCreationDate,
    cr.AnswerOwner
from CombinedResults cr
where (cr.CloseDate is null or cr.CloseDate > now() - interval '1 year')
  and (cr.OwnerReputation > 1000 or cr.GoldBadges > 0)
union
select
    p.Id as QuestionId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    u.DisplayName as OwnerName,
    u.Reputation as OwnerReputation,
    0 as GoldBadges,
    0 as SilverBadges,
    0 as BronzeBadges,
    0 as TagBasedBadges,
    null as CloseDate,
    null as CloseReason,
    0 as CommentCount,
    0::numeric as AvgCommentLength,
    0 as UniqueCommenters,
    0 as QuestionsCount,
    0 as AnswersCount,
    0 as CommentsCount,
    null as LastPostDate,
    null as FirstPostDate,
    null as LastCommentDate,
    null as FirstCommentDate,
    null as TagName,
    null as AnswerId,
    null as AnswerScore,
    null as AnswerCreationDate,
    null as AnswerOwner
from Posts p
left join Users u on u.Id = p.OwnerUserId
where p.PostTypeId = 1
  and p.Score > 50
  and p.ViewCount > 10000
  and not exists (
      select 1 from CombinedResults cr where cr.QuestionId = p.Id
  )
order by Score desc, ViewCount desc
limit 50;