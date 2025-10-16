-- {"query": "878.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2372} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        array[t.TagName] as TagPath,
        1 as Level
    from Tags t
    where t.IsModeratorOnly = 0
    
    union all
    
    select
        t.Id,
        t.TagName,
        t.Count,
        rth.TagPath || t.TagName,
        rth.Level + 1
    from Tags t
    join RecursiveTagHierarchy rth on t.Id <> rth.Id
    where t.IsModeratorOnly = 0 and not t.TagName = any(rth.TagPath) and rth.Level < 3
),
UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        coalesce(sum(case when b.TagBased = 1 then 1 else 0 end),0) as TagBasedBadges
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
),
PostWithVotesAndComments as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        coalesce(v.UpVotes,0) as UpVotes,
        coalesce(v.DownVotes,0) as DownVotes,
        coalesce(c.CommentCount,0) as CommentCount
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    left join (
        select
            PostId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on v.VoteTypeId = vt.Id
        group by PostId
    ) v on p.Id = v.PostId
    left join (
        select
            PostId,
            count(*) as CommentCount
        from Comments
        group by PostId
    ) c on p.Id = c.PostId
),
RankedAnswers as (
    select
        a.Id,
        a.ParentId,
        a.Score,
        a.ViewCount,
        a.CreationDate,
        row_number() over (partition by a.ParentId order by a.Score desc, a.ViewCount desc, a.CreationDate asc) as AnswerRank
    from Posts a
    where a.PostTypeId = 2
),
QuestionAnalysis as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.Tags,
        q.OwnerUserId,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.TagBasedBadges,
        pa.AnswerRank,
        pa.Id as AnswerId,
        pa.Score as AnswerScore,
        pa.ViewCount as AnswerViewCount,
        ph.CloseDate,
        cl.Name as CloseReason,
        case
            when q.ClosedDate is not null then 'Closed'
            else 'Open'
        end as Status,
        -- String expressions combining tags and question title
        concat_ws(' | ', q.Title, substring(q.Tags from 2 for char_length(q.Tags) - 2)) as TitleAndTags,
        -- Complex boolean expression with NULL logic
        case
            when ub.GoldBadges + ub.SilverBadges + ub.BronzeBadges > 10 and q.ViewCount > 1000 and (ph.CloseDate is null or ph.CloseDate > q.CreationDate) then true
            else false
        end as PopularActiveQuestion
    from Posts q
    left join Users u on q.OwnerUserId = u.Id
    left join UserBadgeCounts ub on u.Id = ub.UserId
    left join RankedAnswers pa on pa.ParentId = q.Id and pa.AnswerRank = 1
    left join (
        select distinct PostId, min(CreationDate) as CloseDate from PostHistory
        where PostHistoryTypeId = 10
        group by PostId
    ) ph on ph.PostId = q.Id
    left join CloseReasonTypes cl on ph.PostId = q.Id and ph.PostId = q.Id
    where q.PostTypeId = 1
),
PostsWithLinkInfo as (
    select
        p.Id,
        p.Title,
        p.PostTypeId,
        p.CreationDate,
        p.OwnerUserId,
        pl.LinkTypeId,
        lt.Name as LinkTypeName,
        pl.RelatedPostId,
        rp.Title as RelatedPostTitle
    from Posts p
    left join PostLinks pl on p.Id = pl.PostId
    left join LinkTypes lt on pl.LinkTypeId = lt.Id
    left join Posts rp on pl.RelatedPostId = rp.Id
),
AggregatedUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        count(distinct c.Id) as TotalComments,
        count(distinct v.Id) filter (where vt.Name = 'UpMod') as TotalUpVotesGiven,
        count(distinct v.Id) filter (where vt.Name = 'DownMod') as TotalDownVotesGiven,
        min(p.CreationDate) as FirstPostDate,
        max(p.CreationDate) as LastPostDate,
        -- Window function for running total of posts per user ordered by CreationDate
        sum(1) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as RunningPostCount
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join VoteTypes vt on v.VoteTypeId = vt.Id
    group by u.Id, u.DisplayName
),
ClosedQuestionsWithDupes as (
    select distinct
        q.Id as QuestionId,
        q.Title,
        q.ClosedDate,
        q.OwnerUserId,
        dup.RelatedPostId as DuplicateOfId,
        dupPost.Title as DuplicateOfTitle,
        crt.Name as CloseReasonName
    from Posts q
    inner join PostHistory ph on q.Id = ph.PostId and ph.PostHistoryTypeId = 10
    left join PostLinks dup on q.Id = dup.PostId and dup.LinkTypeId = 3
    left join Posts dupPost on dup.RelatedPostId = dupPost.Id
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where q.PostTypeId = 1
),
HighActivityUsers as (
    select
        u.Id,
        u.DisplayName,
        count(p.Id) as QuestionsPosted,
        count(a.Id) as AnswersPosted,
        count(b.Id) as BadgesEarned,
        count(c.Id) as CommentsMade,
        count(v.Id) filter (where vt.Name = 'UpMod') as UpVotesCast,
        count(v.Id) filter (where vt.Name = 'DownMod') as DownVotesCast,
        dense_rank() over (order by count(p.Id) desc, count(a.Id) desc) as ActivityRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
    left join Badges b on b.UserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join VoteTypes vt on v.VoteTypeId = vt.Id
    group by u.Id, u.DisplayName
    having count(p.Id) > 10 or count(a.Id) > 20
)
select
    qa.QuestionId,
    qa.Title,
    qa.Status,
    qa.PopularActiveQuestion,
    qa.GoldBadges,
    qa.SilverBadges,
    qa.BronzeBadges,
    qa.TagBasedBadges,
    qa.AnswerId,
    qa.AnswerScore,
    qa.AnswerViewCount,
    qa.CloseReason,
    pal.LinkTypeName,
    pal.RelatedPostTitle,
    aua.TotalPosts,
    aua.TotalComments,
    aua.TotalUpVotesGiven,
    aua.TotalDownVotesGiven,
    aua.RunningPostCount,
    cqd.DuplicateOfTitle as DuplicateOf,
    ha.DisplayName as ActiveUserName,
    ha.QuestionsPosted,
    ha.AnswersPosted,
    ha.BadgesEarned,
    ha.CommentsMade,
    ha.UpVotesCast,
    ha.DownVotesCast,
    rth.TagName,
    rth.Level,
    rth.TagPath
from QuestionAnalysis qa
left join PostsWithLinkInfo pal on qa.QuestionId = pal.Id
left join AggregatedUserActivity aua on qa.OwnerUserId = aua.UserId
left join ClosedQuestionsWithDupes cqd on qa.QuestionId = cqd.QuestionId
left join HighActivityUsers ha on qa.OwnerUserId = ha.Id
left join RecursiveTagHierarchy rth on position(rth.TagName in qa.Tags) > 0
where qa.Score > 0 and (qa.CloseDate is null or qa.CloseDate > qa.CreationDate)
union
select
    qa.QuestionId,
    qa.Title,
    qa.Status,
    qa.PopularActiveQuestion,
    qa.GoldBadges,
    qa.SilverBadges,
    qa.BronzeBadges,
    qa.TagBasedBadges,
    qa.AnswerId,
    qa.AnswerScore,
    qa.AnswerViewCount,
    qa.CloseReason,
    null as LinkTypeName,
    null as RelatedPostTitle,
    aua.TotalPosts,
    aua.TotalComments,
    aua.TotalUpVotesGiven,
    aua.TotalDownVotesGiven,
    aua.RunningPostCount,
    null as DuplicateOf,
    ha.DisplayName as ActiveUserName,
    ha.QuestionsPosted,
    ha.AnswersPosted,
    ha.BadgesEarned,
    ha.CommentsMade,
    ha.UpVotesCast,
    ha.DownVotesCast,
    rth.TagName,
    rth.Level,
    rth.TagPath
from QuestionAnalysis qa
left join AggregatedUserActivity aua on qa.OwnerUserId = aua.UserId
left join HighActivityUsers ha on qa.OwnerUserId = ha.Id
left join RecursiveTagHierarchy rth on position(rth.TagName in qa.Tags) > 0
where not exists (
    select 1 from PostsWithLinkInfo pal where pal.Id = qa.QuestionId
)
order by qa.Score desc nulls last, qa.ViewCount desc nulls last, qa.CreationDate asc
limit 100;